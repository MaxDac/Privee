defmodule PriveeWeb.SessionRegistrationLive do
  use PriveeWeb, :live_view

  alias Privee.SessionNameProvider
  alias Privee.Sessions
  alias Privee.Sessions.Session

  @handle_new_session_registration "handle_new_session_registration"

  @impl true
  def mount(params, _session, socket) do
    changeset = Sessions.change_session_registration(%Session{})

    # Check if there's a code parameter to auto-enable quick session
    is_quick = Map.has_key?(params, "code")
    target_session_code = Map.get(params, "code")

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign(target_session_code: target_session_code)
      |> assign_automatic_session_name()
      |> assign_form(changeset)
      |> maybe_set_quick_session(is_quick)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"session" => session_params}, socket) do
    case Sessions.register_session(session_params) do
      {:ok, session} ->
        changeset = Sessions.change_session_registration(session)

        {:noreply,
         socket
         |> push_event(@handle_new_session_registration, %{session_name: session.session_name})
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

  defp maybe_set_quick_session(socket, is_quick) when is_quick do
    # When code is present, automatically set is_quick to true
    changeset = Sessions.change_session_registration(%Session{}, %{"is_quick" => true})
    assign_form(socket, changeset)
  end

  defp maybe_set_quick_session(socket, _), do: socket

  def quick_session?(form) do
    form[:is_quick].value == true or form[:is_quick].value == "true"
  end
end
