defmodule Privee.Repo.Migrations.WipePreKyberPrekeyBundles do
  use Ecto.Migration

  # PQXDH requires a signed Kyber prekey in every bundle: bundles published by
  # X3DH clients cannot start sessions, so clients republish on next visit.
  def up do
    execute "UPDATE sessions SET prekey_bundle = NULL"
  end

  def down, do: :ok
end
