defmodule Privee.PreKeyStoreConcurrencyTest do
  use Privee.DataCase, async: false

  alias Privee.PreKeyStore

  import Privee.PreKeyFixtures
  import Privee.SessionsFixtures

  test "concurrent fetches never serve the same one-time prekey twice" do
    s = session_fixture(%{session_name: Ecto.UUID.generate()})
    :ok = PreKeyStore.publish_identity(s.id, bundle_attrs(opk_ids: 1..10))

    ids =
      1..20
      |> Task.async_stream(fn _ -> PreKeyStore.fetch_bundle(s.id) end, timeout: :infinity)
      |> Enum.map(fn {:ok, {:ok, b, _}} -> b.one_time_prekey && b.one_time_prekey.key_id end)
      |> Enum.reject(&is_nil/1)

    assert Enum.sort(ids) == Enum.to_list(1..10)
  end
end
