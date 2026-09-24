defmodule Privee.Chats.TableOwner do
  @moduledoc """
  Owns the public ETS tables used by `Privee.Chats` and `Privee.RateLimiter`, and
  periodically sweeps expired entries.

  This process is intentionally minimal: reads and writes go directly to ETS from
  the caller process. Only table ownership and the periodic sweep live here.
  """

  use GenServer

  alias Privee.Chats
  alias Privee.RateLimiter

  @default_sweep_interval_ms :timer.minutes(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Chats.create_tables()
    RateLimiter.create_table()

    interval = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)
    schedule_sweep(interval)

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sweep, %{interval: interval} = state) do
    Chats.sweep()
    RateLimiter.sweep()
    schedule_sweep(interval)
    {:noreply, state}
  end

  defp schedule_sweep(:infinity), do: :ok
  defp schedule_sweep(interval), do: Process.send_after(self(), :sweep, interval)
end
