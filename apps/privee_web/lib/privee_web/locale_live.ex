defmodule PriveeWeb.LocaleLive do
  @moduledoc "Changes presentation in the existing LiveView without touching conversation state."

  use Gettext, backend: PriveeWeb.Gettext
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias PriveeWeb.Locale

  def on_mount(:default, _params, session, socket) do
    params = if connected?(socket), do: get_connect_params(socket) || %{}, else: %{}
    locale = Locale.put_locale(Map.get(params, "locale", session["locale"]))

    {:cont,
     socket
     |> assign(:locale, locale)
     |> attach_hook(:locale, :handle_event, &handle_event/3)}
  end

  defp handle_event("set_locale", %{"locale" => locale}, socket) do
    if Locale.valid?(locale) do
      Locale.put_locale(locale)

      {:halt,
       socket
       |> assign(:locale, locale)
       |> clear_flash()
       |> clear_form_errors()
       |> push_event("locale_changed", %{locale: locale})}
    else
      {:halt, put_flash(socket, :error, gettext("This language is not supported."))}
    end
  end

  defp handle_event("locale_persistence_failed", _params, socket) do
    {:halt, put_flash(socket, :error, gettext("Your language preference could not be saved."))}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp clear_form_errors(%{assigns: %{form: %Phoenix.HTML.Form{} = form}} = socket) do
    source =
      case form.source do
        %Ecto.Changeset{} = changeset -> %{changeset | errors: [], action: nil}
        source -> source
      end

    socket
    |> assign(:form, %{form | source: source, errors: []})
    |> maybe_clear_check_errors()
  end

  defp clear_form_errors(socket), do: socket

  defp maybe_clear_check_errors(%{assigns: %{check_errors: _}} = socket),
    do: assign(socket, :check_errors, false)

  defp maybe_clear_check_errors(socket), do: socket
end
