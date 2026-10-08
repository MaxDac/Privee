defmodule PriveeWeb.SessionLoginLive do
  use PriveeWeb, :live_view

  def mount(_params, _session, socket) do
    session_name = Phoenix.Flash.get(socket.assigns.flash, :session_name)
    form = to_form(%{"session_name" => session_name}, as: "session")
    {:ok, assign(socket, form: form)}
  end

  def handle_event("validate", %{"session" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: "session"))}
  end
end
