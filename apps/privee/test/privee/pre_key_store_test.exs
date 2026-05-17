defmodule Privee.PreKeyStoreTest do
  use ExUnit.Case, async: false

  alias Privee.PreKeyStore

  @sample_bundle %{
    identity_key: "test_identity_key_base64",
    registration_id: 12345,
    signed_prekey: %{
      key_id: 1,
      public_key: "test_spk_base64",
      signature: "test_spk_signature_base64"
    },
    one_time_prekeys: [
      %{key_id: 1, public_key: "opk_1_base64"},
      %{key_id: 2, public_key: "opk_2_base64"},
      %{key_id: 3, public_key: "opk_3_base64"}
    ]
  }

  setup do
    # Start a fresh PreKeyStore for each test
    case GenServer.whereis(PreKeyStore) do
      nil -> start_supervised!(PreKeyStore)
      pid -> pid
    end

    # Clean up any previous test data
    PreKeyStore.remove_bundle(999)
    PreKeyStore.remove_bundle(1000)
    :ok
  end

  describe "register_bundle/2" do
    test "registers a prekey bundle for a session" do
      assert :ok = PreKeyStore.register_bundle(999, @sample_bundle)
      assert PreKeyStore.has_bundle?(999)
    end

    test "overwrites existing bundle on re-register" do
      PreKeyStore.register_bundle(999, @sample_bundle)
      new_bundle = %{@sample_bundle | identity_key: "new_identity_key"}
      assert :ok = PreKeyStore.register_bundle(999, new_bundle)

      {:ok, result} = PreKeyStore.get_bundle(999)
      assert result.identity_key == "new_identity_key"
    end
  end

  describe "get_bundle/1" do
    test "returns the bundle with a consumed one-time prekey" do
      PreKeyStore.register_bundle(999, @sample_bundle)
      {:ok, result} = PreKeyStore.get_bundle(999)

      assert result.identity_key == "test_identity_key_base64"
      assert result.registration_id == 12345
      assert result.signed_prekey == @sample_bundle.signed_prekey
      assert result.one_time_prekey == %{key_id: 1, public_key: "opk_1_base64"}
    end

    test "consumes one-time prekeys in order" do
      PreKeyStore.register_bundle(999, @sample_bundle)

      {:ok, r1} = PreKeyStore.get_bundle(999)
      assert r1.one_time_prekey.key_id == 1

      {:ok, r2} = PreKeyStore.get_bundle(999)
      assert r2.one_time_prekey.key_id == 2

      {:ok, r3} = PreKeyStore.get_bundle(999)
      assert r3.one_time_prekey.key_id == 3
    end

    test "returns nil one_time_prekey when all are consumed" do
      bundle = %{@sample_bundle | one_time_prekeys: [%{key_id: 1, public_key: "only_one"}]}
      PreKeyStore.register_bundle(999, bundle)

      {:ok, _} = PreKeyStore.get_bundle(999)
      {:ok, result} = PreKeyStore.get_bundle(999)

      assert result.one_time_prekey == nil
    end

    test "returns error when session not found" do
      assert {:error, :not_found} = PreKeyStore.get_bundle(9999)
    end
  end

  describe "has_bundle?/1" do
    test "returns false when no bundle registered" do
      refute PreKeyStore.has_bundle?(9999)
    end

    test "returns true when bundle is registered" do
      PreKeyStore.register_bundle(999, @sample_bundle)
      assert PreKeyStore.has_bundle?(999)
    end
  end

  describe "remove_bundle/1" do
    test "removes a registered bundle" do
      PreKeyStore.register_bundle(999, @sample_bundle)
      assert :ok = PreKeyStore.remove_bundle(999)
      refute PreKeyStore.has_bundle?(999)
    end

    test "succeeds even if bundle doesn't exist" do
      assert :ok = PreKeyStore.remove_bundle(9999)
    end
  end

  describe "replenish_prekeys/2" do
    test "appends new one-time prekeys to existing bundle" do
      bundle = %{@sample_bundle | one_time_prekeys: [%{key_id: 1, public_key: "opk_1"}]}
      PreKeyStore.register_bundle(999, bundle)

      new_prekeys = [
        %{key_id: 4, public_key: "opk_4"},
        %{key_id: 5, public_key: "opk_5"}
      ]

      assert :ok = PreKeyStore.replenish_prekeys(999, new_prekeys)

      # Consume all and verify order
      {:ok, r1} = PreKeyStore.get_bundle(999)
      assert r1.one_time_prekey.key_id == 1

      {:ok, r2} = PreKeyStore.get_bundle(999)
      assert r2.one_time_prekey.key_id == 4

      {:ok, r3} = PreKeyStore.get_bundle(999)
      assert r3.one_time_prekey.key_id == 5
    end

    test "returns error when session not found" do
      assert {:error, :not_found} = PreKeyStore.replenish_prekeys(9999, [])
    end
  end
end
