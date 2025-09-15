defmodule Privee.Repo.Migrations.AllowNullHashedRecoveryPhraseForQuickSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      modify :hashed_recovery_phrase, :citext, null: true
    end
  end
end
