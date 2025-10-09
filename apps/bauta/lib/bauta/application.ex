defmodule Bauta.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Run migrations on startup if explicitly requested
    if System.get_env("TRIGGER_STARTUP_MIGRATION") == "true" do
      migrate()
    end

    children = [
      Bauta.Repo,
      {DNSCluster,
       query: Application.get_env(:bauta, :dns_cluster_query) || :ignore, log: :info},
      {Phoenix.PubSub, name: Bauta.PubSub}
      # Start a worker by calling: Bauta.Worker.start_link(arg)
      # {Bauta.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Bauta.Supervisor)
  end

  defp migrate do
    for repo <- Application.fetch_env!(:bauta, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
