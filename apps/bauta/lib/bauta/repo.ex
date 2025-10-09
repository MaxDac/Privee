defmodule Bauta.Repo do
  use Ecto.Repo,
    otp_app: :bauta,
    adapter: Ecto.Adapters.Postgres
end
