defmodule Privee.Repo.Migrations.AddIsQuickFieldToSession do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :is_quick, :boolean, null: false, default: false
    end
  end
end
