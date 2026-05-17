defmodule Privee.PreKeyStore do
  @moduledoc """
  ETS-based GenServer to store, serve, and consume Signal Protocol prekey bundles.

  Each session registers a prekey bundle containing:
  - identity_key (public)
  - registration_id
  - signed_prekey (keyId, publicKey, signature)
  - one_time_prekeys (list of {keyId, publicKey})

  One-time prekeys are consumed (deleted) after being served to a requesting party.
  """

  use GenServer

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
  Registers a prekey bundle for a session.
  """
  @spec register_bundle(non_neg_integer(), prekey_bundle()) :: :ok
  def register_bundle(session_id, bundle) do
    GenServer.call(__MODULE__, {:register_bundle, session_id, bundle})
  end

  @doc """
  Gets the prekey bundle for a session, consuming one one-time prekey.
  Returns the bundle with a single one-time prekey (or none if exhausted).
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
  Removes the prekey bundle for a session (e.g., on session deletion).
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
    :ets.insert(@table_name, {session_id, bundle})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_bundle, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, bundle}] ->
        {one_time_prekey, remaining} = consume_one_time_prekey(bundle.one_time_prekeys)

        updated_bundle = %{bundle | one_time_prekeys: remaining}
        :ets.insert(@table_name, {session_id, updated_bundle})

        response = %{
          identity_key: bundle.identity_key,
          registration_id: bundle.registration_id,
          signed_prekey: bundle.signed_prekey,
          one_time_prekey: one_time_prekey
        }

        {:reply, {:ok, response}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:has_bundle, session_id}, _from, state) do
    result = :ets.lookup(@table_name, session_id) != []
    {:reply, result, state}
  end

  @impl true
  def handle_call({:remove_bundle, session_id}, _from, state) do
    :ets.delete(@table_name, session_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:replenish_prekeys, session_id, new_prekeys}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, bundle}] ->
        updated_bundle = %{bundle | one_time_prekeys: bundle.one_time_prekeys ++ new_prekeys}
        :ets.insert(@table_name, {session_id, updated_bundle})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  defp consume_one_time_prekey([]), do: {nil, []}
  defp consume_one_time_prekey([first | rest]), do: {first, rest}
end
