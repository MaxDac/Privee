defmodule Privee.Repo.Migrations.AddPrekeyBundleToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :prekey_bundle, :map
    end
  end
end
