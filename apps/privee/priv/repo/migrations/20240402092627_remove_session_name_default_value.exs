defmodule Privee.Repo.Migrations.RemoveSessionNameDefaultValue do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      modify :public_key, :text, null: false, default: nil
    end
  end
end
