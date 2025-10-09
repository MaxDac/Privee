defmodule Bauta.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Bauta.Repo,
      {DNSCluster, query: Application.get_env(:bauta, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bauta.PubSub}
      # Start a worker by calling: Bauta.Worker.start_link(arg)
      # {Bauta.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Bauta.Supervisor)
  end
end
