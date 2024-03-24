defmodule PriveeWeb.SessionLoginLive do
  use PriveeWeb, :live_view

  def mount(_params, _session, socket) do
    session_name = live_flash(socket.assigns.flash, :session_name)
    form = to_form(%{"session_name" => session_name}, as: "session")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
