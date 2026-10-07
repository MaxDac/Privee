defmodule PriveeWeb.App.SessionChannel do
  @moduledoc """
  The `session` channel of the app socket: Signal key management for the
  authenticated session (see `PriveeWeb.SignalKeys` for the events) and
  content-free notifications.

  Replies always have the `ok` status; failures carry an `error` field, like the
  LiveView events.

  Server pushes:

    * `replenish_prekeys` - the one-time prekey pool is running low
    * `identity_superseded` - `%{identity_key}` was published by another device
    * `message_received` - `%{message_id, from_session_name}`: a new message
      arrived; it must be fetched through the `chat:<from_session_name>` channel
  """

  use PriveeWeb, :channel

  alias Privee.PreKeyStore
  alias Privee.Sessions.Message
  alias PriveeWeb.Endpoint
  alias PriveeWeb.Events
  alias PriveeWeb.SignalKeys

  require Logger

  @message_received_event "message_received"

  @impl true
  def join("session", _params, socket) do
    session = socket.assigns.current_session
    :ok = Endpoint.subscribe(SignalKeys.owner_topic(session.id))
    :ok = Endpoint.subscribe(Events.receiver_topic(session.id))
    {:ok, assign(socket, :signal_identity_key, PreKeyStore.identity_key(session.id))}
  end

  @impl true
  def handle_in(event, params, socket) do
    if event in SignalKeys.events() do
      case SignalKeys.run(event, socket.assigns.current_session.id, params) do
        {:ok, reply, :unchanged} ->
          {:reply, {:ok, reply}, socket}

        {:ok, reply, identity_key} ->
          {:reply, {:ok, reply}, assign(socket, :signal_identity_key, identity_key)}

        {:error, reason} ->
          Logger.debug("Signal key event #{event} failed: #{inspect(reason)}")
          {:reply, {:ok, %{error: to_string(reason)}}, socket}
      end
    else
      {:reply, {:ok, %{error: "unknown_event"}}, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: event, payload: payload}, socket) do
    cond do
      event == SignalKeys.opk_low_event() ->
        push(socket, "replenish_prekeys", %{})
        {:noreply, socket}

      event == SignalKeys.identity_reset_event() ->
        push(socket, "identity_superseded", %{identity_key: payload.identity_key})
        {:noreply, assign(socket, :signal_identity_key, payload.identity_key)}

      event == @message_received_event ->
        push_message_received(socket, payload)
        {:noreply, socket}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp push_message_received(socket, %Message{} = message) do
    if message.to == socket.assigns.current_session.id do
      push(socket, "message_received", %{
        message_id: message.id,
        from_session_name: message.sender_session_name
      })
    end
  end

  defp push_message_received(_socket, _payload), do: :ok
end
