defmodule PriveeWeb.SessionRegistrationLive do
  use PriveeWeb, :live_view

  alias Privee.SessionNameProvider
  alias Privee.Sessions
  alias Privee.Sessions.Session

  @copy_to_clipboard_client_action_key "copy_to_clipboard"

  @impl true
  def mount(_params, _session, socket) do
    changeset = Sessions.change_session_registration(%Session{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_automatic_session_name()
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"session" => session_params}, socket) do
    case Sessions.register_session(session_params) do
      {:ok, session} ->
        changeset = Sessions.change_session_registration(session)

        {:noreply,
         socket
         |> push_event(@copy_to_clipboard_client_action_key, %{session_name: session.session_name})
         |> assign(trigger_submit: true)
         |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(check_errors: true)
         |> assign_form(changeset)}
    end
  end

  @impl true
  def handle_event("validate", %{"session" => session_params}, socket) do
    changeset =
      Sessions.change_session_registration(%Session{}, session_params)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "session")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp assign_automatic_session_name(socket) do
    if connected?(socket) do
      {:ok, automatic_session_name} = SessionNameProvider.generate_new_available_session_name()
      assign(socket, :automatic_session_name, automatic_session_name)
    else
      assign(socket, :automatic_session_name, "")
    end
  end
end
