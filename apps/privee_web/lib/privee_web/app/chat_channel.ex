defmodule PriveeWeb.App.ChatChannel do
  @moduledoc """
  The `chat:<peer session name>` channel of the app socket: a privee between the
  authenticated session and the peer. Events are the ones of
  `PriveeWeb.ChatActions` (`open_conversation`, `request_peer_bundle`,
  `send_message`, `fetch_messages`).

  Replies always have the `ok` status; failures carry an `error` field, like the
  LiveView events.

  Server pushes:

    * `new_message` - a serialized message (see
      `PriveeWeb.Chat.ChatHelpers.serialize_message/2`) of this conversation
    * `peer_keys_ready` - (content-free) the peer published new keys
  """

  use PriveeWeb, :channel

  alias Privee.PreKeyStore
  alias Privee.Sessions.Message
  alias PriveeWeb.ChatActions
  alias PriveeWeb.Endpoint
  alias PriveeWeb.Events
  alias PriveeWeb.SignalKeys

  import PriveeWeb.Chat.ChatHelpers, only: [serialize_message: 2]

  @chat_created_event "chat_created"

  @impl true
  def join("chat:" <> peer_session_name, _params, socket) do
    me = socket.assigns.current_session

    case ChatActions.find_peer(me, peer_session_name) do
      {:ok, peer} ->
        :ok = Endpoint.subscribe(Events.chat_topic(me.id, peer.id))
        :ok = Endpoint.subscribe(SignalKeys.peer_topic(peer.id))

        {:ok, %{peer_session_name: peer.session_name},
         socket
         |> assign(:peer, peer)
         |> assign(:signal_identity_key, PreKeyStore.identity_key(me.id))}

      :error ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("open_conversation", _params, socket) do
    %{current_session: me, peer: peer} = socket.assigns
    {:reply, {:ok, ChatActions.open_conversation(me, peer)}, socket}
  end

  def handle_in("request_peer_bundle", _params, socket) do
    %{current_session: me, peer: peer} = socket.assigns
    {:reply, {:ok, ChatActions.request_peer_bundle(me, peer)}, socket}
  end

  def handle_in("send_message", params, socket) do
    %{current_session: me, peer: peer, signal_identity_key: key} = socket.assigns
    {reply, key} = ChatActions.send_message(me, peer, params, key)
    {:reply, {:ok, reply}, assign(socket, :signal_identity_key, key)}
  end

  def handle_in("fetch_messages", params, socket) do
    %{current_session: me, peer: peer} = socket.assigns
    {:reply, {:ok, ChatActions.fetch_messages(me, peer, params)}, socket}
  end

  def handle_in(_event, _params, socket),
    do: {:reply, {:ok, %{error: "unknown_event"}}, socket}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: @chat_created_event, payload: payload}, socket) do
    case payload do
      %Message{} = message ->
        push(socket, "new_message", serialize_message(message, socket.assigns.current_session.id))

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: event}, socket) do
    if event == SignalKeys.prekeys_available_event() do
      push(socket, "peer_keys_ready", %{})
    end

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
