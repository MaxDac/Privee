defmodule Privee.Repo.Migrations.AddUniqueIndexToSessionName do
  use Ecto.Migration

  def change do
    create unique_index(:sessions, [:session_name])
  end
end
