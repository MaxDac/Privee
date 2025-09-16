defmodule Privee.Repo.Migrations.AddHasLoggedFieldToSession do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :has_logged, :boolean, null: false, default: false
    end
  end
end
