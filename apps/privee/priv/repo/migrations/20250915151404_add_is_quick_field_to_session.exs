defmodule Privee.Repo.Migrations.AddIsQuickFieldToSession do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :is_quick, :boolean, null: true, default: false
    end
  end
end
