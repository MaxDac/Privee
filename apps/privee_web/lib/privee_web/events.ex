defmodule PriveeWeb.Events do
  @moduledoc """
  Exposes the functions needed to configure and use the Phoenix `PubSub` server
  in the context of the chatting notifications.
  """

  alias Phoenix.LiveView.Socket

  alias Privee.Sessions.Message
  alias PriveeWeb.Endpoint

  import Phoenix.LiveView

  @chat_created_event "chat_created"
  @message_received_event "message_received"
  @js_event "trigger_notification"

  @doc """
  Creates a subscription for the current LiveView socket to receive broadcasted
  new messages in the chat the session is currently following.

  It returns {:ok, %Socket{}} if the subscription succeeded, {:error, %Socket{}}
  otherwise.
  """
  def subscribe_to_chat_events(
        %Socket{} = socket,
        current_session_id,
        chatting_to_id
      ) do
    if connected?(socket) do
      topic = get_chat_subscription_topic(current_session_id, chatting_to_id)
      Endpoint.subscribe(topic)
    else
      {:error, :socket_not_connected}
    end
  end

  @doc """
  Creates a subscription for the current LiveView socket to receive broadcasted
  new messages to the current session_id.

  It returns {:ok, %Socket{}} if the subscription succeeded, {:error, %Socket{}}
  otherwise.
  """
  def subscribe_to_receiving_events(
        %Socket{} = socket,
        current_session_id
      ) do
    if connected?(socket) do
      topic = get_receiver_subscription_topic(current_session_id)
      Endpoint.subscribe(topic)
    else
      {:error, :socket_not_connected}
    end
  end

  @doc """
  Broadcasts the insertion of a new message both to the current chat topic, and to the
  user currently in the chat.
  """
  def broadcast_new_message(%Message{from: from, to: to} = message) do
    chat_topic = get_chat_subscription_topic(from, to)
    receiver_topic = get_receiver_subscription_topic(to)

    Endpoint.broadcast(chat_topic, @chat_created_event, message)
    Endpoint.broadcast(receiver_topic, @message_received_event, message)
  end

  defp get_chat_subscription_topic(session_id_1, session_id_2) do
    if session_id_1 > session_id_2 do
      "chat:#{session_id_1}:#{session_id_2}"
    else
      "chat:#{session_id_2}:#{session_id_1}"
    end
  end

  defp get_receiver_subscription_topic(session_id) do
    "receiver:#{session_id}"
  end

  @doc """
  Sends a notification event to the client, to trigger in turn a notification.
  It executes a preliminary filter on the notifications that must be sent to the
  client, based on the current and selected session, and on the payload
  information:

  1. If the current session is not the receiver, the notification will not be sent.

  2. If the sender is the selected session the user is currently chatting with,
     the notification **will be sent**, because the Javascript must check
     whether the user is currently focusing on the chatting windows.
     a. If the user is focusing on the chatting windows, the client will not
        trigger the notification.
     b. Otherwise, it will trigger the notification.
  """
  def send_notification_event_to_client(socket, payload) do
    IO.inspect({socket.assigns, payload}, label: "send_notification_event_to_client")
    case {socket.assigns, payload} do
      # If the message is from the session the user is currently chatting with, send notification with warning.
      {
        %{current_session: %{id: to_id}, selected_session: %{id: from_id}},
        %{to: to_id, from: from_id, sender_session_name: sender_session_name, text: text}
      } ->
        push_event(socket, @js_event, %{
          session_name: sender_session_name,
          text: text,
          check_focus: true
        })

      # If the user is the receiver, but the sender is not the selected session, send the notification.
      {
        %{current_session: %{id: to_id}},
        %{to: to_id, sender_session_name: sender_session_name, text: text}
      } ->
        push_event(socket, @js_event, %{
          session_name: sender_session_name,
          text: text,
          check_focus: false
        })

      # In all other cases, do not send the notification.
      _ ->
        socket
    end
  end
end
