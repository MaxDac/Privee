defmodule PriveeWeb.JsFlash do
  @moduledoc """
  Lets client-side JavaScript raise server-side flash messages by pushing a
  `"js_flash"` event. Attached to every LiveView through `use PriveeWeb, :live_view`.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  @kinds %{"info" => :info, "error" => :error, "warning" => :warning}

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :js_flash, :handle_event, &handle_event/3)}
  end

  defp handle_event("js_flash", %{"message" => message} = params, socket) do
    kind = Map.get(@kinds, params["kind"], :info)
    {:halt, put_flash(socket, kind, build_message(params["title"], message))}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp build_message(nil, message), do: message
  defp build_message(title, message), do: "#{title} #{message}"
end
