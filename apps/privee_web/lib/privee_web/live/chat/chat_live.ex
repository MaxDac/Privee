defmodule PriveeWeb.Chat.ChatLive do
  @moduledoc """
  A privee: the end-to-end encrypted chat between the current session and the
  selected one.

  The server never sees plaintext. The client (see `assets/js/hooks/chat-hooks.mjs`)
  talks to this LiveView through the reply-based events documented in
  `PriveeWeb.ChatActions`: `open_conversation`, `request_peer_bundle`,
  `send_message` and `fetch_messages`.

  Server pushes: `peer_keys_ready` (content-free) when the peer publishes keys.
  """

  use PriveeWeb, :live_view

  alias Privee.Chats
  alias Privee.Sessions.Message

  alias PriveeWeb.ChatActions
  alias PriveeWeb.Events
  alias PriveeWeb.SignalKeys

  import PriveeWeb.Chat.ChatHelpers

  require Logger

  embed_templates "components/*"

  @chat_created_event "chat_created"
  @message_received_event "message_received"
  @prekeys_available_event "prekeys_available"

  @impl true
  def mount(%{"session" => selected_session_name}, _session, socket) do
    case socket
         |> assign(:selected_session_name, selected_session_name)
         |> assign_selected_session() do
      {:cont, socket} ->
        {:ok,
         socket
         |> assign_existing_messages()
         |> subscribe_to_events()}

      {:halt, socket} ->
        {:ok, socket}
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:info, gettext("You have to select a session to continue"))
     |> push_navigate(to: ~p"/privee")}
  end

  @impl true
  def handle_event("open_conversation", _params, socket) do
    %{current_session: me, selected_session: peer} = socket.assigns
    {:reply, ChatActions.open_conversation(me, peer), socket}
  end

  def handle_event("request_peer_bundle", _params, socket) do
    %{current_session: me, selected_session: peer} = socket.assigns
    {:reply, ChatActions.request_peer_bundle(me, peer), socket}
  end

  def handle_event("send_message", params, socket) do
    %{current_session: me, selected_session: peer, signal_identity_key: key} = socket.assigns
    {reply, key} = ChatActions.send_message(me, peer, params, key)
    {:reply, reply, assign(socket, :signal_identity_key, key)}
  end

  def handle_event("fetch_messages", params, socket) do
    %{current_session: me, selected_session: peer} = socket.assigns
    {:reply, ChatActions.fetch_messages(me, peer, params), socket}
  end

  # Legacy events from a cached client.
  def handle_event(event, _params, socket) do
    Logger.debug("Unexpected chat event #{inspect(event)}")

    {:noreply,
     put_flash(socket, :error, gettext("The application was updated. Please reload the page."))}
  end

  @impl true
  def handle_info(%{event: @prekeys_available_event}, socket) do
    {:noreply, push_event(socket, "peer_keys_ready", %{})}
  end

  def handle_info(%{event: @chat_created_event, payload: %Message{} = message}, socket) do
    {:noreply, assign_message(socket, message)}
  end

  def handle_info(%{event: @message_received_event, payload: payload}, socket) do
    {:noreply, Events.send_notification_event_to_client(socket, payload)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp assign_selected_session(
         %{assigns: %{selected_session_name: selected_session_name, current_session: me}} =
           socket
       ) do
    case ChatActions.find_peer(me, selected_session_name) do
      {:ok, selected_session} ->
        {:cont, assign(socket, :selected_session, selected_session)}

      :error ->
        {:halt,
         socket
         |> put_flash(:info, gettext("You have to select a session to continue"))
         |> push_navigate(to: ~p"/privee")}
    end
  end

  defp assign_existing_messages(
         %{assigns: %{current_session: current_session, selected_session: selected_session}} =
           socket
       ) do
    {epoch, messages} = Chats.latest_messages(current_session.id, selected_session.id)
    {last_message, messages} = parse_messages(messages)

    socket
    |> assign(:epoch, epoch)
    |> assign(:last_message, last_message)
    |> stream_configure(:messages, dom_id: &message_dom_id/1)
    |> stream(:messages, messages)
  end

  defp subscribe_to_events(
         %{assigns: %{current_session: current_session, selected_session: selected_session}} =
           socket
       ) do
    if connected?(socket) do
      with :ok <-
             Events.subscribe_to_chat_events(socket, current_session.id, selected_session.id),
           :ok <- Events.subscribe_to_receiving_events(socket, current_session.id),
           :ok <- PriveeWeb.Endpoint.subscribe(SignalKeys.peer_topic(selected_session.id)) do
        socket
      else
        error ->
          Logger.warning("Failed to subscribe to chat events: '#{inspect(error)}'.")
          socket
      end
    else
      socket
    end
  end

  defp assign_message(%{assigns: %{last_message: last_message}} = socket, message) do
    new_message = add_message(message, last_message)

    socket
    |> assign(:last_message, new_message)
    |> assign(:epoch, new_message.epoch)
    |> stream_insert(:messages, new_message)
  end
end
