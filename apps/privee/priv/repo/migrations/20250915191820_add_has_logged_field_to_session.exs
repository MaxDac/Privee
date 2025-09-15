defmodule Privee.Repo.Migrations.AddHasLoggedFieldToSession do
  use Ecto.Migration

  def change do
    add :has_logged, :boolean, null: false, default: false
  end
end
