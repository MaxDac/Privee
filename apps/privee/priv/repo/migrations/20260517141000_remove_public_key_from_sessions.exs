defmodule Privee.Repo.Migrations.RemovePublicKeyFromSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      remove :public_key, :text
    end
  end
end
