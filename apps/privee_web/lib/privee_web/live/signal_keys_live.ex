defmodule PriveeWeb.SignalKeysLive do
  @moduledoc """
  LiveView lifecycle hook managing the current session's published Signal key
  material. Attached through `on_mount` to every authenticated LiveView, so the
  client can publish and replenish keys wherever it is.

  Client events (all reply-based, scoped to `current_session`):

    * `signal_status` - `%{identity_key, opk_count, max_opk_id, max_age_ms}`
    * `publish_identity` - initial bundle
    * `reset_identity` - replaces the bundle; other devices become superseded
    * `rotate_signed_prekey` - `%{identity_key, signed_prekey}`
    * `add_prekeys` - `%{identity_key, one_time_prekeys}`

  Server pushes:

    * `replenish_prekeys` - the one-time prekey pool is running low
    * `identity_superseded` - `%{identity_key}` was published by another device

  The published identity key is kept in the `:signal_identity_key` assign.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Privee.Chats
  alias Privee.PreKeyStore
  alias PriveeWeb.Endpoint

  require Logger

  @events ~w(signal_status publish_identity reset_identity rotate_signed_prekey add_prekeys)

  @opk_low_event "opk_low"
  @identity_reset_event "identity_reset"
  @prekeys_available_event "prekeys_available"

  @opk_low_threshold 20

  def on_mount(:default, _params, _session, %{assigns: %{current_session: session}} = socket)
      when not is_nil(session) do
    socket =
      if connected?(socket) do
        :ok = Endpoint.subscribe(owner_topic(session.id))
        assign(socket, :signal_identity_key, PreKeyStore.identity_key(session.id))
      else
        assign(socket, :signal_identity_key, nil)
      end

    {:cont,
     socket
     |> attach_hook(:signal_keys_events, :handle_event, &handle_event/3)
     |> attach_hook(:signal_keys_info, :handle_info, &handle_info/2)}
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  @doc "Topic on which the owner of `session_id` receives key management notifications."
  def owner_topic(session_id), do: "prekeys_owner:#{session_id}"

  @doc "Topic on which peers of `session_id` learn that its keys became available."
  def peer_topic(session_id), do: "prekeys:#{session_id}"

  @doc "Notifies the owner that its one-time prekeys are running low, if they are."
  def maybe_notify_opk_low(session_id, remaining) when remaining < @opk_low_threshold do
    Endpoint.broadcast(owner_topic(session_id), @opk_low_event, %{remaining: remaining})
  end

  def maybe_notify_opk_low(_session_id, _remaining), do: :ok

  # Event hook

  defp handle_event(event, params, socket) when event in @events do
    session_id = socket.assigns.current_session.id
    params = if is_map(params), do: params, else: %{}

    case run(event, session_id, params, socket) do
      {:ok, reply, socket} ->
        {:halt, reply, socket}

      {:error, reason} ->
        Logger.debug("Signal key event #{event} failed: #{inspect(reason)}")
        {:halt, %{error: to_string(reason)}, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp run("signal_status", session_id, _params, socket) do
    status = PreKeyStore.status(session_id)
    {:ok, Map.put(status, :max_age_ms, Chats.config().max_age_ms), socket}
  end

  defp run("publish_identity", session_id, params, socket) do
    with :ok <- PreKeyStore.publish_identity(session_id, params) do
      Endpoint.broadcast(peer_topic(session_id), @prekeys_available_event, %{})
      {:ok, %{ok: true}, assign(socket, :signal_identity_key, params["identity_key"])}
    end
  end

  defp run("reset_identity", session_id, params, socket) do
    with :ok <- PreKeyStore.reset_identity(session_id, params) do
      identity_key = params["identity_key"]
      :ok = Chats.end_conversations(session_id)

      Endpoint.broadcast(owner_topic(session_id), @identity_reset_event, %{
        identity_key: identity_key
      })

      Endpoint.broadcast(peer_topic(session_id), @prekeys_available_event, %{})
      {:ok, %{ok: true}, assign(socket, :signal_identity_key, identity_key)}
    end
  end

  defp run("rotate_signed_prekey", session_id, params, socket) do
    with :ok <-
           PreKeyStore.rotate_signed_prekey(
             session_id,
             params["identity_key"],
             params["signed_prekey"]
           ) do
      {:ok, %{ok: true}, socket}
    end
  end

  defp run("add_prekeys", session_id, params, socket) do
    with :ok <-
           PreKeyStore.add_one_time_prekeys(
             session_id,
             params["identity_key"],
             params["one_time_prekeys"]
           ) do
      Endpoint.broadcast(peer_topic(session_id), @prekeys_available_event, %{})
      {:ok, %{ok: true}, socket}
    end
  end

  # Info hook

  defp handle_info(%{event: @opk_low_event}, socket) do
    {:halt, push_event(socket, "replenish_prekeys", %{})}
  end

  defp handle_info(%{event: @identity_reset_event, payload: %{identity_key: key}}, socket) do
    {:halt,
     socket
     |> assign(:signal_identity_key, key)
     |> push_event("identity_superseded", %{identity_key: key})}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
