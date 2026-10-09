defmodule Privee.Sessions.Janitor do
  @moduledoc """
  Periodically deletes expired session tokens and unused sessions (see
  `Privee.Sessions.delete_unused_sessions/1`), as sessions are meant to be
  volatile.

  Options (from `config :privee, Privee.Sessions.Janitor`):

    * `:interval_ms` - time between runs, `:infinity` disables the job
      (default: 6 hours; the first run is one minute after start);
    * `:retention_days` - days without a sign-in after which a session is
      deleted (default: 90, never less than the token validity).
  """

  use GenServer

  alias Privee.Sessions

  require Logger

  @default_interval_ms :timer.hours(6)
  @default_retention_days 90
  @first_run_ms :timer.minutes(1)

  def start_link(opts \\ []) do
    opts = Keyword.merge(Application.get_env(:privee, __MODULE__, []), opts)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Runs a cleanup now. Returns `{deleted_tokens, deleted_sessions}`."
  def run(retention_days \\ @default_retention_days) do
    tokens = Sessions.delete_expired_session_tokens()
    sessions = Sessions.delete_unused_sessions(retention_days)
    {tokens, sessions}
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    retention = Keyword.get(opts, :retention_days, @default_retention_days)
    schedule(interval, min(@first_run_ms, interval))
    {:ok, %{interval: interval, retention: retention}}
  end

  @impl true
  def handle_info(:cleanup, %{interval: interval, retention: retention} = state) do
    try do
      {tokens, sessions} = run(retention)

      if tokens + sessions > 0,
        do: Logger.info("Deleted #{tokens} expired tokens and #{sessions} unused sessions")
    rescue
      e -> Logger.warning("Session cleanup failed: #{Exception.message(e)}")
    end

    schedule(interval, interval)
    {:noreply, state}
  end

  defp schedule(:infinity, _delay), do: :ok
  defp schedule(_interval, delay), do: Process.send_after(self(), :cleanup, delay)
end
