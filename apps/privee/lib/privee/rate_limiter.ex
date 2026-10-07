defmodule Privee.RateLimiter do
  @moduledoc """
  Fixed-window counters stored in a public ETS table owned by
  `Privee.Chats.TableOwner`. Counters are shared across processes (sockets, tabs).
  """

  @table :rate_limits

  @doc false
  def create_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
    end

    :ok
  end

  @doc """
  Registers a hit for `key`. Returns `:ok` while at most `limit` hits happened in
  the current window of `window_ms`, `:limited` afterwards.
  """
  @spec hit(term(), pos_integer(), pos_integer(), integer()) :: :ok | :limited
  def hit(key, limit, window_ms, now \\ System.system_time(:millisecond)) do
    bucket_key = {key, div(now, window_ms)}

    try do
      count = :ets.update_counter(@table, bucket_key, {2, 1}, {bucket_key, 0, now + window_ms})
      if count <= limit, do: :ok, else: :limited
    rescue
      ArgumentError -> :ok
    end
  end

  @doc "Deletes expired windows."
  def sweep(now \\ System.system_time(:millisecond)) do
    if :ets.whereis(@table) != :undefined do
      :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    end

    :ok
  end
end
