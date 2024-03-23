defmodule PriveeWeb.Chat.ChatLive do
  @moduledoc """
  This component represents a privee, or a chat where two sessions can actually talk.
  """

  use PriveeWeb, :chat_live_view

  alias Privee.Chats
  alias Privee.Sessions
  alias Privee.Sessions.Message

  alias PriveeWeb.Events

  import PriveeWeb.Chat.ChatHelpers

  require Logger

  embed_templates "components/*"

  @chat_created_event "chat_created"
  @message_received_event "message_received"

  @impl true
  def mount(%{"session" => selected_session_name}, _session, socket) do
    case socket
         |> assign(:selected_session_name, selected_session_name)
         |> assign_selected_session() do
      {:cont, socket} ->
        {:ok,
         socket
         |> assign_existing_messages()
         |> subscribe_to_events()
         |> assign_form()}

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
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply,
     socket
     |> assign_form(params)}
  end

  @impl true
  def handle_event("create", %{"message" => params}, socket) do
    {:noreply,
     socket
     |> deliver_message(params)
     |> assign_form()}
  end

  @impl true
  def handle_info(%{event: @chat_created_event, payload: message}, socket) do
    {:noreply, assign_message(socket, message)}
  end

  @impl true
  def handle_info(%{event: @message_received_event, payload: payload}, socket) do
    {:noreply, Events.send_notification_event_to_client(socket, payload)}
  end

  defp assign_selected_session(
         %{assigns: %{selected_session_name: selected_session_name}} = socket
       ) do
    if selected_session = Sessions.get_session_by_session_name(selected_session_name) do
      {:cont, assign(socket, :selected_session, selected_session)}
    else
      {:halt,
       socket
       |> put_flash(:info, "You have to select a session to continue")
       |> push_navigate(to: ~p"/privee")}
    end
  end

  defp assign_existing_messages(
         %{
           assigns: %{
             current_session: current_session,
             selected_session: selected_session
           }
         } = socket
       ) do
    messages = Chats.get_messages(current_session.id, selected_session.id)
    assign(socket, :messages, parse_messages(messages))
  end

  defp assign_existing_messages(socket), do: assign(socket, :messages, [])

  defp assign_form(socket, attrs \\ %{}) do
    form =
      Sessions.change_message(%Message{}, attrs)
      |> to_form()

    assign(socket, :form, form)
  end

  defp subscribe_to_events(
         %{assigns: %{current_session: current_session, selected_session: selected_session}} =
           socket
       ) do
    if connected?(socket) do
      with :ok <-
             Events.subscribe_to_chat_events(socket, current_session.id, selected_session.id),
           :ok <- Events.subscribe_to_receiving_events(socket, current_session.id) do
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

  defp deliver_message(socket, params) do
    changeset = Sessions.change_message(%Message{}, params)

    if changeset.valid? do
      message = Ecto.Changeset.apply_changes(changeset)
      Chats.create_message(message)
      Events.broadcast_new_message(message)
    end

    socket
  end

  defp assign_message(%{assigns: %{messages: messages}} = socket, message) do
    assign(socket, :messages, add_message(message, messages))
  end
end
