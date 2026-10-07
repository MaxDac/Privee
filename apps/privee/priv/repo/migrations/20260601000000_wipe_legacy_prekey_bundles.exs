defmodule Privee.Repo.Migrations.WipeLegacyPrekeyBundles do
  use Ecto.Migration

  # Bundles published by the legacy P-256 implementation are incompatible with
  # the Signal Protocol (Curve25519) client: clients republish on next visit.
  def up do
    execute "UPDATE sessions SET prekey_bundle = NULL"
  end

  def down, do: :ok
end
