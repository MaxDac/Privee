defmodule Privee.Repo.Migrations.OverhaulingSessionTable do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      remove :hashed_session_name
      remove :confirmed_at
      remove :recovery_phrase

      # Removing encryption to session name and adding it to the recovery field
      add :session_name, :string, null: false
      add :hashed_recovery_phrase, :citext, null: false
    end
  end
end
