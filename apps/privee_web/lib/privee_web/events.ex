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
      IO.inspect(topic, label: "chat subscribing")
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
      IO.inspect(topic, label: "receiving subscribing")
      Endpoint.subscribe(topic)
    else
      {:error, :socket_not_connected}
    end
  end

  @doc """
  Broadcasts the insertion of a new message both to the current chat topic, and to the
  user currently in the chat.
  """
  def broadcast_new_message(%Message{to: to, from: from} = message) do
    chat_topic = get_chat_subscription_topic(to, from)
    receiver_topic = get_receiver_subscription_topic(to)
    
    IO.inspect({chat_topic, receiver_topic}, label: "broadcasting")

    Endpoint.broadcast(chat_topic, @chat_created_event, message)
    Endpoint.broadcast(receiver_topic, @chat_created_event, message)
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
end
