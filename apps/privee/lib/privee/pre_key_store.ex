defmodule Privee.PreKeyStore do
  @moduledoc """
  Manages Signal Protocol prekey bundles with database persistence and ETS caching.

  Each session registers a prekey bundle containing:
  - identity_key (public)
  - registration_id
  - signed_prekey (keyId, publicKey, signature)
  - one_time_prekeys (list of {keyId, publicKey})

  Bundles are stored in the sessions table (prekey_bundle column) for persistence
  across server restarts, with ETS as a runtime cache for fast lookups.
  One-time prekeys are consumed (popped) after being served.
  """

  use GenServer

  alias Privee.Repo
  alias Privee.Sessions.Session
  import Ecto.Query

  @table_name :signal_prekey_bundles

  @type prekey :: %{key_id: non_neg_integer(), public_key: String.t()}

  @type signed_prekey :: %{
          key_id: non_neg_integer(),
          public_key: String.t(),
          signature: String.t()
        }

  @type prekey_bundle :: %{
          identity_key: String.t(),
          registration_id: non_neg_integer(),
          signed_prekey: signed_prekey(),
          one_time_prekeys: list(prekey())
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a prekey bundle for a session. Persists to database and caches in ETS.
  """
  @spec register_bundle(non_neg_integer(), prekey_bundle()) :: :ok
  def register_bundle(session_id, bundle) do
    GenServer.call(__MODULE__, {:register_bundle, session_id, bundle})
  end

  @doc """
  Gets the prekey bundle for a session, consuming one one-time prekey.
  Returns the bundle with a single one-time prekey (or none if exhausted).
  Checks ETS cache first, falls back to database.
  """
  @spec get_bundle(non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def get_bundle(session_id) do
    GenServer.call(__MODULE__, {:get_bundle, session_id})
  end

  @doc """
  Checks whether a prekey bundle exists for a given session.
  """
  @spec has_bundle?(non_neg_integer()) :: boolean()
  def has_bundle?(session_id) do
    GenServer.call(__MODULE__, {:has_bundle, session_id})
  end

  @doc """
  Removes the prekey bundle for a session.
  """
  @spec remove_bundle(non_neg_integer()) :: :ok
  def remove_bundle(session_id) do
    GenServer.call(__MODULE__, {:remove_bundle, session_id})
  end

  @doc """
  Replenishes one-time prekeys for a session.
  """
  @spec replenish_prekeys(non_neg_integer(), list(prekey())) :: :ok | {:error, :not_found}
  def replenish_prekeys(session_id, new_prekeys) do
    GenServer.call(__MODULE__, {:replenish_prekeys, session_id, new_prekeys})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    _ = create_table()
    {:ok, []}
  end

  defp create_table do
    if :ets.whereis(@table_name) == :undefined do
      :ets.new(@table_name, [:set, :protected, :named_table])
    end
  end

  @impl true
  def handle_call({:register_bundle, session_id, bundle}, _from, state) do
    # Normalize to string keys for consistent JSONB storage
    normalized = normalize_bundle(bundle)
    # Persist to database
    persist_bundle(session_id, normalized)
    # Cache in ETS
    :ets.insert(@table_name, {session_id, normalized})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_bundle, session_id}, _from, state) do
    bundle = get_cached_or_load(session_id)

    case bundle do
      nil ->
        {:reply, {:error, :not_found}, state}

      bundle ->
        {one_time_prekey, remaining} = consume_one_time_prekey(bundle["one_time_prekeys"] || [])

        updated_bundle = Map.put(bundle, "one_time_prekeys", remaining)
        :ets.insert(@table_name, {session_id, updated_bundle})
        persist_bundle(session_id, updated_bundle)

        response = %{
          identity_key: bundle["identity_key"],
          registration_id: bundle["registration_id"],
          signed_prekey: atomize_keys(bundle["signed_prekey"]),
          one_time_prekey: atomize_keys(one_time_prekey)
        }

        {:reply, {:ok, response}, state}
    end
  end

  @impl true
  def handle_call({:has_bundle, session_id}, _from, state) do
    result = get_cached_or_load(session_id) != nil
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_bundle, session_id}, _from, state) do
    :ets.delete(@table_name, session_id)
    persist_bundle(session_id, nil)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:replenish_prekeys, session_id, new_prekeys}, _from, state) do
    case get_cached_or_load(session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      bundle ->
        existing = bundle["one_time_prekeys"] || []

        updated_bundle =
          Map.put(bundle, "one_time_prekeys", existing ++ stringify_keys(new_prekeys))

        :ets.insert(@table_name, {session_id, updated_bundle})
        persist_bundle(session_id, updated_bundle)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:clear_cache, session_id}, _from, state) do
    :ets.delete(@table_name, session_id)
    {:reply, :ok, state}
  end

  # Private helpers

  defp get_cached_or_load(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, bundle}] ->
        bundle

      [] ->
        # Load from database
        case load_from_db(session_id) do
          nil ->
            nil

          bundle ->
            :ets.insert(@table_name, {session_id, bundle})
            bundle
        end
    end
  end

  defp load_from_db(session_id) do
    query = from s in Session, where: s.id == ^session_id, select: s.prekey_bundle
    Repo.one(query)
  rescue
    _ -> nil
  end

  defp persist_bundle(session_id, bundle) do
    from(s in Session, where: s.id == ^session_id)
    |> Repo.update_all(set: [prekey_bundle: bundle])
  rescue
    _ -> :ok
  end

  defp consume_one_time_prekey([]), do: {nil, []}
  defp consume_one_time_prekey([first | rest]), do: {first, rest}

  defp atomize_keys(nil), do: nil

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, fn map ->
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end)
  end

  defp normalize_bundle(bundle) do
    bundle
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("signed_prekey", nil, fn
      nil -> nil
      spk -> Map.new(spk, fn {k, v} -> {to_string(k), v} end)
    end)
    |> Map.update("one_time_prekeys", [], fn
      nil -> []
      prekeys -> stringify_keys(prekeys)
    end)
  end
end
