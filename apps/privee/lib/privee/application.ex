defmodule Privee.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize OpenTelemetry (only when OTEL_ACTIVE=true)
    if System.get_env("OTEL_ACTIVE") == "true" do
      OpentelemetryEcto.setup([:privee, :repo])
    end

    # Run migrations on startup if explicitly requested
    if System.get_env("TRIGGER_STARTUP_MIGRATION") == "true" do
      migrate()
    end

    children = [
      Privee.Repo,
      {DNSCluster,
       query: Application.get_env(:privee, :dns_cluster_query) || :ignore, log: :info},
      {Phoenix.PubSub, name: Privee.PubSub}
      # Start a worker by calling: Privee.Worker.start_link(arg)
      # {Privee.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Privee.Supervisor)
  end

  defp migrate do
    for repo <- Application.fetch_env!(:privee, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
