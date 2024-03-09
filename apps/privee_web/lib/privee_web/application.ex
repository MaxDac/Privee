defmodule PriveeWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PriveeWeb.Telemetry,
      # Start a worker by calling: PriveeWeb.Worker.start_link(arg)
      # {PriveeWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      PriveeWeb.Endpoint,
      {Cluster.Supervisor, [get_topologies(), [name: GuildsWeb.ClusterSupervisor]]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PriveeWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_topologies do
    is_prod? = System.get_env("MIX_ENV")

    strategy =
      if is_prod? do
        Cluster.Strategy.Kubernetes.DNS
      else
        Cluster.Strategy.Gossip
      end

    [
      privee: [
        strategy: strategy,
        config: [
          service: "privee-app-svc-headless",
          application_name: "privee"
        ]
      ]
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PriveeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
