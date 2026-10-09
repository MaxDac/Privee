defmodule PriveeWeb.NotificationsLive do
  @moduledoc """
  LiveView lifecycle hook delivering the new-message notifications of the
  current session. Attached through `on_mount` to every authenticated
  LiveView, so a LiveView does not subscribe to the receiver topic itself.

  On a `message_received` broadcast it pushes the content-free
  `trigger_notification` event (see `PriveeWeb.Events.send_notification_event_to_client/2`).
  """

  import Phoenix.LiveView

  alias PriveeWeb.Events

  require Logger

  @message_received_event "message_received"

  def on_mount(:default, _params, _session, %{assigns: %{current_session: session}} = socket)
      when not is_nil(session) do
    if connected?(socket) do
      with {:error, reason} <- Events.subscribe_to_receiving_events(socket, session.id) do
        Logger.warning("Could not subscribe to receiving events '#{inspect(reason)}'.")
      end
    end

    {:cont, attach_hook(socket, :notifications, :handle_info, &handle_info/2)}
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  defp handle_info(%{event: @message_received_event, payload: payload}, socket) do
    {:halt, Events.send_notification_event_to_client(socket, payload)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
