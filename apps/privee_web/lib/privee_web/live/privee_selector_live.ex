defmodule PriveeWeb.PriveeSelectorLive do
  @moduledoc """
  The chat screen. This is the only screen that the user will be able to see.
  """

  use PriveeWeb, :live_view

  alias PriveeWeb.Events

  alias Privee.Sessions
  alias Privee.Sessions.PriveeForm

  require Logger

  @message_received_event "message_received"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> subscribe_to_events()
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"privee_form" => params}, socket) do
    {:noreply,
     socket
     |> assign_form(params)}
  end

  @impl true
  def handle_event("create", %{"privee_form" => params}, socket) do
    changeset = get_privee_form_changeset(params, socket)

    if changeset.valid? do
      selected_session = Ecto.Changeset.get_field(changeset, :session_name)

      {:noreply,
       socket
       |> push_navigate(to: ~p"/chat/#{selected_session}")}
    else
      {:noreply,
       socket
       |> assign_form(params)}
    end
  end

  @impl true
  def handle_info(%{event: @message_received_event, payload: payload}, socket) do
    {:noreply, Events.send_notification_event_to_client(socket, payload)}
  end

  defp assign_form(socket, params \\ %{}) do
    changeset = get_privee_form_changeset(params, socket)

    # Not showing the error when first accessing the page
    changeset = if params == %{}, do: changeset, else: assign_changeset_action(changeset)

    assign(socket, :form, to_form(changeset))
  end

  defp get_privee_form_changeset(params, socket) do
    %PriveeForm{}
    |> Sessions.change_privee_form(params)
    |> validate_session_name_not_same_as_session(socket)
  end

  defp validate_session_name_not_same_as_session(
         changeset,
         %{assigns: %{current_session: current_session}} = _socket
       ) do
    current_session_name = current_session.session_name

    Ecto.Changeset.validate_change(changeset, :session_name, fn
      field, ^current_session_name ->
        [{field, "You selected your session name"}]

      _, _ ->
        []
    end)
  end

  defp subscribe_to_events(%{assigns: %{current_session: current_session}} = socket) do
    if connected?(socket) do
      case Events.subscribe_to_receiving_events(socket, current_session.id) do
        :ok ->
          socket

        error ->
          Logger.warning("Could not subscribe to receiving events '#{inspect(error)}'.")
          socket
      end
    else
      socket
    end
  end
end
