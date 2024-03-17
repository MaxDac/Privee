defmodule PriveeWeb.SessionRegistrationLive do
  use PriveeWeb, :live_view

  alias Privee.Sessions
  alias Privee.Sessions.Session
  alias Privee.SessionNameProvider

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto sm:max-w-sm md:max-w-md">
      <.header class="text-center">
        Register for an account
        <:subtitle>
          Already registered?
          <.link navigate={~p"/"} class="font-semibold text-brand hover:underline">
            Sign in
          </.link>
          to your account now.
        </:subtitle>

        <:description>
          To register a session, you have to define a <strong>Session Name</strong>, a series of alphanumeric characters
          divided by hyphens with a minimum length of 24 characters, and a recovery phrase, that can contain only
          alphabetic character, spaces and punctuation.
        </:description>
      </.header>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/sessions/log_in?_action=registered"}
        method="post"
      >
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input
          field={@form[:session_name]}
          type="search"
          label="Session Name"
          placeholder="Write your own session name"
          value={@automatic_session_name}
          phx-debounce="1000"
          required
        />

        <.input
          field={@form[:recovery_phrase]}
          type="textarea"
          label="Recovery phrase"
          placeholder="Write your preferred citation. This will be used to recover the session, so keep it saved."
          rows="5"
          phx-debounce="1000"
          required
        />

        <:actions>
          <.button phx-disable-with="Creating account..." class="w-full">Create an account</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

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
    changeset = Sessions.change_session_registration(%Session{}, session_params) |> IO.inspect(label: "validation changeset")
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
