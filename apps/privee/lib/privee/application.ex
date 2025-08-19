defmodule Privee.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Privee.Repo,
      {DNSCluster, query: Application.get_env(:privee, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Privee.PubSub},
      # Start a worker by calling: Privee.Worker.start_link(arg)
      # {Privee.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Privee.Supervisor)
  end
end
