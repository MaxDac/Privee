defmodule PriveeWeb.Chat.ChatLive do
  @moduledoc """
  A privee: the end-to-end encrypted chat between the current session and the
  selected one.

  The server never sees plaintext. The client (see `assets/js/hooks/chat-hooks.mjs`)
  talks to this LiveView through reply-based events:

    * `open_conversation` - `%{epoch}`: the conversation epoch sessions bind to.
    * `request_peer_bundle` - `%{bundle}`: the peer's public prekey bundle. At most
      #{3} one-time prekeys per requester/peer pair are popped every 10 minutes.
    * `send_message` - `%{type, body, client_nonce, epoch, identity_key}` ->
      `%{id, seq, epoch, client_nonce}` or `%{error}`.
    * `fetch_messages` - `%{epoch, after_seq}` -> `%{messages, next_cursor}`.

  Server pushes: `peer_keys_ready` (content-free) when the peer publishes keys.
  """

  use PriveeWeb, :chat_live_view

  alias Privee.Chats
  alias Privee.PreKeyStore
  alias Privee.RateLimiter
  alias Privee.Sessions
  alias Privee.Sessions.Message

  alias PriveeWeb.Events
  alias PriveeWeb.SignalKeysLive

  import PriveeWeb.Chat.ChatHelpers

  require Logger

  embed_templates "components/*"

  @chat_created_event "chat_created"
  @message_received_event "message_received"
  @prekeys_available_event "prekeys_available"

  @opk_pops_per_window 3
  @opk_window_ms :timer.minutes(10)
  @max_page_size 200

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
     |> put_flash(:info, "You have to select a session to continue")
     |> push_navigate(to: ~p"/privee")}
  end

  @impl true
  def handle_event("open_conversation", _params, socket) do
    %{current_session: me, selected_session: peer} = socket.assigns

    case Chats.open_conversation(me.id, peer.id) do
      {:ok, epoch} -> {:reply, %{epoch: epoch}, socket}
      {:error, reason} -> {:reply, %{error: to_string(reason)}, socket}
    end
  end

  def handle_event("request_peer_bundle", _params, socket) do
    %{current_session: me, selected_session: peer} = socket.assigns

    pop? =
      RateLimiter.hit({:opk_pop, me.id, peer.id}, @opk_pops_per_window, @opk_window_ms) == :ok

    case PreKeyStore.fetch_bundle(peer.id, pop_one_time_prekey: pop?) do
      {:ok, bundle, remaining} ->
        if pop?, do: SignalKeysLive.maybe_notify_opk_low(peer.id, remaining)
        {:reply, %{peer_id: peer.id, bundle: bundle}, socket}

      {:error, :not_found} ->
        {:reply, %{peer_id: peer.id, error: "not_found"}, socket}
    end
  end

  def handle_event("send_message", %{"epoch" => epoch} = params, socket)
      when is_binary(epoch) do
    %{current_session: me, selected_session: peer} = socket.assigns
    socket = refresh_identity_key(socket, params["identity_key"])

    changeset =
      Sessions.change_message(
        %Message{from: me.id, to: peer.id, sender_session_name: me.session_name},
        params
      )

    cond do
      is_nil(socket.assigns.signal_identity_key) or
          params["identity_key"] != socket.assigns.signal_identity_key ->
        {:reply, %{error: "superseded"}, socket}

      not changeset.valid? ->
        {:reply, %{error: "invalid"}, socket}

      true ->
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Chats.create_message(epoch)
        |> reply_to_send(socket)
    end
  end

  def handle_event("fetch_messages", %{"epoch" => epoch, "after_seq" => after_seq}, socket)
      when is_binary(epoch) and is_integer(after_seq) do
    %{current_session: me, selected_session: peer} = socket.assigns

    {messages, next_cursor} =
      Chats.messages_after(me.id, peer.id, epoch, after_seq, @max_page_size)

    {:reply,
     %{
       messages: Enum.map(messages, &serialize_message(&1, me.id)),
       next_cursor: next_cursor
     }, socket}
  end

  def handle_event(event, _params, socket) when event in ~w(send_message fetch_messages) do
    {:reply, %{error: "invalid"}, socket}
  end

  # Legacy events from a cached client.
  def handle_event(event, _params, socket) do
    Logger.debug("Unexpected chat event #{inspect(event)}")
    {:noreply, put_flash(socket, :error, "The application was updated. Please reload the page.")}
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

  defp reply_to_send({:ok, message}, socket) do
    Events.broadcast_new_message(message)
    {:reply, sent_reply(message), socket}
  end

  defp reply_to_send({:duplicate, message}, socket), do: {:reply, sent_reply(message), socket}

  defp reply_to_send({:error, {:stale_epoch, epoch}}, socket),
    do: {:reply, %{error: "stale_epoch", epoch: epoch}, socket}

  defp reply_to_send({:error, reason}, socket),
    do: {:reply, %{error: to_string(reason)}, socket}

  defp sent_reply(message) do
    %{id: message.id, seq: message.seq, epoch: message.epoch, client_nonce: message.client_nonce}
  end

  defp assign_selected_session(
         %{assigns: %{selected_session_name: selected_session_name, current_session: me}} =
           socket
       ) do
    case Sessions.get_session_by_session_name(selected_session_name) do
      %{id: id} = selected_session when id != me.id ->
        {:cont, assign(socket, :selected_session, selected_session)}

      _ ->
        {:halt,
         socket
         |> put_flash(:info, "You have to select a session to continue")
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
           :ok <- PriveeWeb.Endpoint.subscribe(SignalKeysLive.peer_topic(selected_session.id)) do
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

  # The assign can lag behind the store (e.g. another tab published the identity
  # after this socket mounted): re-read it before rejecting a send as superseded.
  defp refresh_identity_key(%{assigns: %{signal_identity_key: key}} = socket, key)
       when is_binary(key),
       do: socket

  defp refresh_identity_key(socket, _claimed) do
    assign(
      socket,
      :signal_identity_key,
      PreKeyStore.identity_key(socket.assigns.current_session.id)
    )
  end
end
