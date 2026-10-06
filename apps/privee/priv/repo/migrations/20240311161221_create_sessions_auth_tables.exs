defmodule Privee.Repo.Migrations.CreateSessionsAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:sessions) do
      add :recovery_phrase, :citext, null: false
      add :hashed_session_name, :string, null: false
      add :confirmed_at, :naive_datetime
      timestamps()
    end

    create unique_index(:sessions, [:hashed_session_name])

    create table(:sessions_tokens) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      timestamps(updated_at: false)
    end

    create index(:sessions_tokens, [:session_id])
    create unique_index(:sessions_tokens, [:context, :token])
  end
end
