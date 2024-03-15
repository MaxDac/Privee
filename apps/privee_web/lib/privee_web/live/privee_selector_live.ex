defmodule PriveeWeb.PriveeSelectorLive do
  @moduledoc """
  The chat screen. This is the only screen that the user will be able to see.
  """

  use PriveeWeb, :live_view

  alias PriveeWeb.Events

  alias Privee.Sessions
  alias Privee.Sessions.PriveeForm

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto sm:max-w-sm md:max-w-md">
      <.header class="text-center">
        Create a new Privée
        <:subtitle>
          Specify the session name you would like to chat with.
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="privee_form" phx-change="validate" phx-submit="create">
        <.input
          field={@form[:session_name]}
          type="text"
          label="Session Name"
          placeholder="The session name you'd like to contact."
          required
        />

        <:actions>
          <.button phx-disable-with="Creating..." class="w-full">
            Start Privée <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"privee_form" => params}, socket) do
    {:noreply,
     socket
     |> subscribe_to_events()
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
    case Events.subscribe_to_receiving_events(socket, current_session.id) do
      :ok ->
        socket

      error ->
        Logger.warning("Could not subscribe to receiving events '#{inspect(error)}'.")
        socket
    end
  end
end
