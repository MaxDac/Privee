defmodule Privee.Repo.Migrations.CreatePushEndpoints do
  use Ecto.Migration

  def change do
    create table(:push_endpoints) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :session_token_id, references(:sessions_tokens, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false

      timestamps(updated_at: false)
    end

    create index(:push_endpoints, [:session_id])
    create unique_index(:push_endpoints, [:session_token_id])
    create unique_index(:push_endpoints, [:endpoint])
  end
end
