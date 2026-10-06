defmodule Privee.Repo do
  use Ecto.Repo,
    otp_app: :privee,
    adapter: Ecto.Adapters.Postgres
end
