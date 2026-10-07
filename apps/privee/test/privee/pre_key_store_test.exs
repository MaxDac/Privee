defmodule Privee.PreKeyStoreTest do
  use Privee.DataCase, async: true

  alias Privee.PreKeyStore

  import Privee.PreKeyFixtures
  import Privee.SessionsFixtures

  setup do
    %{session: session_fixture(%{session_name: Ecto.UUID.generate()})}
  end

  describe "publish_identity/2" do
    test "stores a valid bundle", %{session: s} do
      attrs = bundle_attrs()
      assert :ok = PreKeyStore.publish_identity(s.id, attrs)
      assert PreKeyStore.identity_key(s.id) == attrs["identity_key"]
      assert PreKeyStore.count_one_time_prekeys(s.id) == 3
    end

    test "is idempotent for the same identity", %{session: s} do
      attrs = bundle_attrs()
      :ok = PreKeyStore.publish_identity(s.id, attrs)
      assert :ok = PreKeyStore.publish_identity(s.id, attrs)
    end

    test "refuses to replace a different identity", %{session: s} do
      :ok = PreKeyStore.publish_identity(s.id, bundle_attrs())
      assert {:error, :already_published} = PreKeyStore.publish_identity(s.id, bundle_attrs())
    end

    test "accepts atom keys", %{session: s} do
      attrs = %{
        identity_key: public_key(),
        registration_id: 1,
        signed_prekey: %{key_id: 1, public_key: public_key(), signature: signature()},
        kyber_prekey: %{key_id: 1, public_key: kyber_public_key(), signature: signature()},
        one_time_prekeys: []
      }

      assert :ok = PreKeyStore.publish_identity(s.id, attrs)
    end

    test "returns not_found for a missing session" do
      assert {:error, :not_found} = PreKeyStore.publish_identity(-1, bundle_attrs())
    end

    for {name, mutate} <- [
          {"short identity key",
           quote(do: &Map.put(&1, "identity_key", Base.encode64(<<5, 1, 2>>)))},
          {"identity key without 0x05 prefix",
           quote(
             do:
               &Map.put(&1, "identity_key", Base.encode64(<<4>> <> :crypto.strong_rand_bytes(32)))
           )},
          {"non base64 key", quote(do: &Map.put(&1, "identity_key", "not base64!"))},
          {"bad signature",
           quote(do: &put_in(&1, ["signed_prekey", "signature"], Base.encode64("short")))},
          {"registration id out of range", quote(do: &Map.put(&1, "registration_id", 0x4000))},
          {"zero opk id",
           quote(
             do: &Map.put(&1, "one_time_prekeys", Privee.PreKeyFixtures.one_time_prekeys([0]))
           )},
          {"duplicate opk ids",
           quote(
             do: &Map.put(&1, "one_time_prekeys", Privee.PreKeyFixtures.one_time_prekeys([1, 1]))
           )},
          {"string key id", quote(do: &put_in(&1, ["signed_prekey", "key_id"], "1"))},
          {"missing kyber prekey", quote(do: &Map.delete(&1, "kyber_prekey"))},
          {"curve25519 key as kyber prekey",
           quote(
             do: &put_in(&1, ["kyber_prekey", "public_key"], Privee.PreKeyFixtures.public_key())
           )},
          {"kyber key without 0x08 prefix",
           quote(
             do:
               &put_in(
                 &1,
                 ["kyber_prekey", "public_key"],
                 Base.encode64(<<5>> <> :crypto.strong_rand_bytes(1568))
               )
           )},
          {"oversized kyber key",
           quote(
             do:
               &put_in(
                 &1,
                 ["kyber_prekey", "public_key"],
                 Base.encode64(<<8>> <> :crypto.strong_rand_bytes(1569))
               )
           )},
          {"bad kyber signature",
           quote(do: &put_in(&1, ["kyber_prekey", "signature"], Base.encode64("short")))}
        ] do
      test "rejects #{name}", %{session: s} do
        attrs = unquote(mutate).(bundle_attrs())
        assert {:error, :invalid_bundle} = PreKeyStore.publish_identity(s.id, attrs)
        refute PreKeyStore.has_bundle?(s.id)
      end
    end

    test "rejects more than the maximum number of opks", %{session: s} do
      attrs = bundle_attrs(opk_ids: 1..(PreKeyStore.max_one_time_prekeys() + 1))
      assert {:error, :too_many_prekeys} = PreKeyStore.publish_identity(s.id, attrs)
    end

    test "rejects unknown keys without creating atoms", %{session: s} do
      attrs = Map.delete(bundle_attrs(), "identity_key")
      assert {:error, :invalid_bundle} = PreKeyStore.publish_identity(s.id, attrs)
    end
  end

  describe "reset_identity/2" do
    test "replaces the identity", %{session: s} do
      :ok = PreKeyStore.publish_identity(s.id, bundle_attrs())
      new = bundle_attrs(opk_ids: [1])
      assert :ok = PreKeyStore.reset_identity(s.id, new)
      assert PreKeyStore.identity_key(s.id) == new["identity_key"]
      assert PreKeyStore.count_one_time_prekeys(s.id) == 1
    end
  end

  describe "rotate_signed_prekey/4" do
    test "replaces the signed and Kyber prekeys for the current identity", %{session: s} do
      attrs = bundle_attrs()
      :ok = PreKeyStore.publish_identity(s.id, attrs)
      spk = %{"key_id" => 2, "public_key" => public_key(), "signature" => signature()}
      kyber = kyber_prekey(2)

      assert :ok = PreKeyStore.rotate_signed_prekey(s.id, attrs["identity_key"], spk, kyber)

      assert {:ok, %{signed_prekey: %{key_id: 2}, kyber_prekey: served}, _} =
               PreKeyStore.fetch_bundle(s.id)

      assert served == %{
               key_id: 2,
               public_key: kyber["public_key"],
               signature: kyber["signature"]
             }
    end

    test "requires a valid Kyber prekey", %{session: s} do
      attrs = bundle_attrs()
      :ok = PreKeyStore.publish_identity(s.id, attrs)
      spk = %{"key_id" => 2, "public_key" => public_key(), "signature" => signature()}

      assert {:error, :invalid_bundle} =
               PreKeyStore.rotate_signed_prekey(s.id, attrs["identity_key"], spk, nil)

      assert {:ok, %{signed_prekey: %{key_id: 1}}, _} = PreKeyStore.fetch_bundle(s.id)
    end

    test "refuses a stale identity", %{session: s} do
      :ok = PreKeyStore.publish_identity(s.id, bundle_attrs())
      spk = %{"key_id" => 2, "public_key" => public_key(), "signature" => signature()}

      assert {:error, :identity_mismatch} =
               PreKeyStore.rotate_signed_prekey(s.id, public_key(), spk, kyber_prekey(2))
    end
  end

  describe "add_one_time_prekeys/3" do
    setup %{session: s} do
      attrs = bundle_attrs()
      :ok = PreKeyStore.publish_identity(s.id, attrs)
      %{ik: attrs["identity_key"]}
    end

    test "appends new ids", %{session: s, ik: ik} do
      assert :ok = PreKeyStore.add_one_time_prekeys(s.id, ik, one_time_prekeys(4..6))
      assert PreKeyStore.count_one_time_prekeys(s.id) == 6
    end

    test "rejects ids already stored", %{session: s, ik: ik} do
      assert {:error, :stale_prekey_ids} =
               PreKeyStore.add_one_time_prekeys(s.id, ik, one_time_prekeys([3, 4]))

      assert PreKeyStore.count_one_time_prekeys(s.id) == 3
    end

    test "rejects ids that were already served", %{session: s, ik: ik} do
      for _ <- 1..3, do: {:ok, _, _} = PreKeyStore.fetch_bundle(s.id)
      assert PreKeyStore.count_one_time_prekeys(s.id) == 0

      assert {:error, :stale_prekey_ids} =
               PreKeyStore.add_one_time_prekeys(s.id, ik, one_time_prekeys([1]))
    end

    test "enforces the cap", %{session: s, ik: ik} do
      max = PreKeyStore.max_one_time_prekeys()

      assert {:error, :too_many_prekeys} =
               PreKeyStore.add_one_time_prekeys(s.id, ik, one_time_prekeys(4..(max + 1)))
    end

    test "refuses a stale identity", %{session: s} do
      assert {:error, :identity_mismatch} =
               PreKeyStore.add_one_time_prekeys(s.id, public_key(), one_time_prekeys([10]))
    end

    test "requires a bundle" do
      other = session_fixture(%{session_name: Ecto.UUID.generate()})

      assert {:error, :not_found} =
               PreKeyStore.add_one_time_prekeys(other.id, public_key(), one_time_prekeys([1]))
    end
  end

  describe "fetch_bundle/2" do
    test "pops one-time prekeys in order until exhausted", %{session: s} do
      :ok = PreKeyStore.publish_identity(s.id, bundle_attrs(opk_ids: [1, 2]))

      assert {:ok, %{one_time_prekey: %{key_id: 1}}, 1} = PreKeyStore.fetch_bundle(s.id)
      assert {:ok, %{one_time_prekey: %{key_id: 2}}, 0} = PreKeyStore.fetch_bundle(s.id)

      assert {:ok, %{one_time_prekey: nil, signed_prekey: %{}}, 0} =
               PreKeyStore.fetch_bundle(s.id)
    end

    test "can serve without popping", %{session: s} do
      :ok = PreKeyStore.publish_identity(s.id, bundle_attrs())

      assert {:ok, %{one_time_prekey: nil}, 3} =
               PreKeyStore.fetch_bundle(s.id, pop_one_time_prekey: false)
    end

    test "returns not_found without a bundle", %{session: s} do
      assert {:error, :not_found} = PreKeyStore.fetch_bundle(s.id)
      assert {:error, :not_found} = PreKeyStore.fetch_bundle(-1)
    end
  end

  test "status/1", %{session: s} do
    assert %{identity_key: nil, opk_count: 0, max_opk_id: 0} = PreKeyStore.status(s.id)
    attrs = bundle_attrs(opk_ids: [2, 7])
    :ok = PreKeyStore.publish_identity(s.id, attrs)
    {:ok, _, _} = PreKeyStore.fetch_bundle(s.id)
    ik = attrs["identity_key"]
    assert %{identity_key: ^ik, opk_count: 1, max_opk_id: 7} = PreKeyStore.status(s.id)
  end

  test "remove_bundle/1", %{session: s} do
    :ok = PreKeyStore.publish_identity(s.id, bundle_attrs())
    assert :ok = PreKeyStore.remove_bundle(s.id)
    refute PreKeyStore.has_bundle?(s.id)
    assert PreKeyStore.identity_key(s.id) == nil
    assert PreKeyStore.count_one_time_prekeys(s.id) == nil
  end
end
