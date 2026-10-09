defmodule Privee.Repo.Migrations.AddLastUsedAtToSessions do
  use Ecto.Migration

  # The last sign-in of a session, used by Privee.Sessions.Janitor. Existing
  # sessions start from the migration time, so none of them is deleted before a
  # full retention period has passed.
  def up do
    alter table(:sessions) do
      add :last_used_at, :naive_datetime
    end

    execute "UPDATE sessions SET last_used_at = timezone('UTC', now())::timestamp(0)"
    create index(:sessions, [:last_used_at])
  end

  def down do
    drop index(:sessions, [:last_used_at])

    alter table(:sessions) do
      remove :last_used_at
    end
  end
end
