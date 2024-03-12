defmodule PriveeWeb.SessionLoginLive do
  use PriveeWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto sm:max-w-sm md:max-w-md">
      <.header class="text-center">
        Sign in to account
        <:subtitle>
          Don't have an account?
          <.link navigate={~p"/sessions/register"} class="font-semibold text-brand hover:underline">
            Sign up
          </.link>
          for an account now.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="login_form"
        action={~p"/sessions/log_in"}
        phx-update="ignore">

        <.input
          field={@form[:session_name]}
          type="text"
          label="Session Name"
          placeholder="Write your session name."
          required />

        <.input
          field={@form[:recovery_phrase]}
          type="textarea"
          label="Recovery phrase"
          placeholder="Your citation."
          rows="5"
          required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
        </:actions>

        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full">
            Sign in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "session")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
