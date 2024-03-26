defmodule Privee.Repo.Migrations.AddPublicKeysToSession do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :public_key, :string,
        null: false,
        # #81 Setting a default value for now, it will have to be removed in another migration.
        default: ""
    end
  end
end
