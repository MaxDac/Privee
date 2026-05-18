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

  @prekey_bundle_event "prekey_bundle"
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
         |> send_prekey_bundle()
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
  def handle_event("register_prekeys", params, socket) do
    session_id = socket.assigns.current_session.id
    Logger.debug("Registering prekeys for session #{session_id}")

    bundle = %{
      identity_key: params["identity_key"],
      registration_id: params["registration_id"],
      signed_prekey: %{
        key_id: params["signed_prekey"]["key_id"],
        public_key: params["signed_prekey"]["public_key"],
        signature: params["signed_prekey"]["signature"]
      },
      one_time_prekeys:
        Enum.map(params["one_time_prekeys"] || [], fn pk ->
          %{key_id: pk["key_id"], public_key: pk["public_key"]}
        end)
    }

    Privee.PreKeyStore.register_bundle(session_id, bundle)

    # Notify anyone waiting for our prekey bundle
    PriveeWeb.Endpoint.broadcast("prekeys:#{session_id}", @prekeys_available_event, %{})

    # After registering our bundle, send the peer's bundle for session establishment
    {:noreply, push_prekey_bundle(socket)}
  end

  @impl true
  def handle_info(%{event: @prekeys_available_event}, socket) do
    # Peer's prekeys just became available - send their bundle to the client
    {:noreply, push_prekey_bundle(socket)}
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
    {last_message, messages} =
      Chats.get_messages(current_session.id, selected_session.id)
      |> parse_messages()

    socket
    |> assign(:last_message, last_message)
    |> stream(:messages, messages)
  end

  defp assign_existing_messages(socket),
    do:
      socket
      |> assign(:last_message, nil)
      |> stream(:messages, [])

  defp assign_form(socket, attrs \\ %{}) do
    form =
      Sessions.change_message(%Message{}, attrs)
      |> to_form()

    assign(socket, :form, form)
  end

  defp send_prekey_bundle(%{assigns: %{selected_session: selected_session}} = socket) do
    case Privee.PreKeyStore.get_bundle(selected_session.id) do
      {:ok, bundle} ->
        Logger.debug("Sending prekey bundle for peer #{selected_session.id}")

        bundle_data = %{
          peer_session_id: selected_session.id,
          identity_key: bundle.identity_key,
          registration_id: bundle.registration_id,
          signed_prekey: bundle.signed_prekey,
          one_time_prekey: bundle.one_time_prekey
        }

        assign(socket, :peer_prekey_bundle, Jason.encode!(bundle_data))

      {:error, :not_found} ->
        Logger.debug("No prekey bundle found for peer #{selected_session.id}")
        assign(socket, :peer_prekey_bundle, nil)
    end
  end

  defp push_prekey_bundle(%{assigns: %{selected_session: selected_session}} = socket) do
    case Privee.PreKeyStore.get_bundle(selected_session.id) do
      {:ok, bundle} ->
        Logger.debug("Sending prekey bundle for peer #{selected_session.id}")

        push_event(socket, @prekey_bundle_event, %{
          peer_session_id: selected_session.id,
          identity_key: bundle.identity_key,
          registration_id: bundle.registration_id,
          signed_prekey: bundle.signed_prekey,
          one_time_prekey: bundle.one_time_prekey
        })

      {:error, :not_found} ->
        socket
    end
  end

  defp subscribe_to_events(
         %{assigns: %{current_session: current_session, selected_session: selected_session}} =
           socket
       ) do
    if connected?(socket) do
      with :ok <-
             Events.subscribe_to_chat_events(socket, current_session.id, selected_session.id),
           :ok <- Events.subscribe_to_receiving_events(socket, current_session.id),
           :ok <- PriveeWeb.Endpoint.subscribe("prekeys:#{selected_session.id}") do
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

  defp assign_message(%{assigns: %{last_message: last_message}} = socket, message) do
    new_message = add_message(message, last_message)

    socket
    |> assign(:last_message, new_message)
    |> stream_insert(:messages, new_message)
  end
end
