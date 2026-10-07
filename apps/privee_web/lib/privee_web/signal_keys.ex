defmodule PriveeWeb.SignalKeys do
  @moduledoc """
  Transport-independent handling of the Signal key management events, shared by
  the LiveView hook (`PriveeWeb.SignalKeysLive`) and the app channel
  (`PriveeWeb.App.SessionChannel`).

  Events (all scoped to the authenticated session):

    * `signal_status` - `%{identity_key, opk_count, max_opk_id, max_age_ms}`
    * `publish_identity` - initial bundle
    * `reset_identity` - replaces the bundle; other devices become superseded
    * `rotate_signed_prekey` - `%{identity_key, signed_prekey, kyber_prekey}`
    * `add_prekeys` - `%{identity_key, one_time_prekeys}`

  Notifications are broadcast on `owner_topic/1` (`opk_low`, `identity_reset`)
  and `peer_topic/1` (`prekeys_available`).
  """

  alias Privee.Chats
  alias Privee.PreKeyStore
  alias PriveeWeb.Endpoint

  @events ~w(signal_status publish_identity reset_identity rotate_signed_prekey add_prekeys)

  @opk_low_event "opk_low"
  @identity_reset_event "identity_reset"
  @prekeys_available_event "prekeys_available"

  @opk_low_threshold 20

  @doc "The key management events handled by `run/3`."
  def events, do: @events

  @doc "Name of the owner notification sent when the one-time prekeys run low."
  def opk_low_event, do: @opk_low_event

  @doc "Name of the owner notification sent when another device resets the identity."
  def identity_reset_event, do: @identity_reset_event

  @doc "Name of the peer notification sent when new keys become available."
  def prekeys_available_event, do: @prekeys_available_event

  @doc "Topic on which the owner of `session_id` receives key management notifications."
  def owner_topic(session_id), do: "prekeys_owner:#{session_id}"

  @doc "Topic on which peers of `session_id` learn that its keys became available."
  def peer_topic(session_id), do: "prekeys:#{session_id}"

  @doc "Notifies the owner that its one-time prekeys are running low, if they are."
  def maybe_notify_opk_low(session_id, remaining) when remaining < @opk_low_threshold do
    Endpoint.broadcast(owner_topic(session_id), @opk_low_event, %{remaining: remaining})
  end

  def maybe_notify_opk_low(_session_id, _remaining), do: :ok

  @doc """
  Runs the key management `event` for `session_id`.

  Returns `{:ok, reply, identity_key}` where `identity_key` is the identity key
  published by this call or `:unchanged`, or `{:error, reason}`.
  """
  @spec run(String.t(), non_neg_integer(), map()) ::
          {:ok, map(), String.t() | :unchanged} | {:error, term()}
  def run(event, session_id, params) when not is_map(params), do: run(event, session_id, %{})

  def run("signal_status", session_id, _params) do
    status = PreKeyStore.status(session_id)
    {:ok, Map.put(status, :max_age_ms, Chats.config().max_age_ms), :unchanged}
  end

  def run("publish_identity", session_id, params) do
    with :ok <- PreKeyStore.publish_identity(session_id, params) do
      Endpoint.broadcast(peer_topic(session_id), @prekeys_available_event, %{})
      {:ok, %{ok: true}, params["identity_key"]}
    end
  end

  def run("reset_identity", session_id, params) do
    with :ok <- PreKeyStore.reset_identity(session_id, params) do
      identity_key = params["identity_key"]
      :ok = Chats.end_conversations(session_id)

      Endpoint.broadcast(owner_topic(session_id), @identity_reset_event, %{
        identity_key: identity_key
      })

      Endpoint.broadcast(peer_topic(session_id), @prekeys_available_event, %{})
      {:ok, %{ok: true}, identity_key}
    end
  end

  def run("rotate_signed_prekey", session_id, params) do
    with :ok <-
           PreKeyStore.rotate_signed_prekey(
             session_id,
             params["identity_key"],
             params["signed_prekey"],
             params["kyber_prekey"]
           ) do
      {:ok, %{ok: true}, :unchanged}
    end
  end

  def run("add_prekeys", session_id, params) do
    with :ok <-
           PreKeyStore.add_one_time_prekeys(
             session_id,
             params["identity_key"],
             params["one_time_prekeys"]
           ) do
      Endpoint.broadcast(peer_topic(session_id), @prekeys_available_event, %{})
      {:ok, %{ok: true}, :unchanged}
    end
  end
end
