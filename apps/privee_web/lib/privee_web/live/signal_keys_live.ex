defmodule PriveeWeb.SignalKeysLive do
  @moduledoc """
  LiveView lifecycle hook managing the current session's published Signal key
  material. Attached through `on_mount` to every authenticated LiveView, so the
  client can publish and replenish keys wherever it is.

  Client events (all reply-based, scoped to `current_session`):

    * `signal_status` - `%{identity_key, opk_count, max_opk_id, max_age_ms}`
    * `publish_identity` - initial bundle
    * `reset_identity` - replaces the bundle; other devices become superseded
    * `rotate_signed_prekey` - `%{identity_key, signed_prekey, kyber_prekey}`
    * `add_prekeys` - `%{identity_key, one_time_prekeys}`

  Server pushes:

    * `replenish_prekeys` - the one-time prekey pool is running low
    * `identity_superseded` - `%{identity_key}` was published by another device

  The published identity key is kept in the `:signal_identity_key` assign.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Privee.PreKeyStore
  alias PriveeWeb.Endpoint
  alias PriveeWeb.SignalKeys

  require Logger

  def on_mount(:default, _params, _session, %{assigns: %{current_session: session}} = socket)
      when not is_nil(session) do
    socket =
      if connected?(socket) do
        :ok = Endpoint.subscribe(owner_topic(session.id))
        assign(socket, :signal_identity_key, PreKeyStore.identity_key(session.id))
      else
        assign(socket, :signal_identity_key, nil)
      end

    {:cont,
     socket
     |> attach_hook(:signal_keys_events, :handle_event, &handle_event/3)
     |> attach_hook(:signal_keys_info, :handle_info, &handle_info/2)}
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  @doc "See `PriveeWeb.SignalKeys.owner_topic/1`."
  defdelegate owner_topic(session_id), to: SignalKeys

  @doc "See `PriveeWeb.SignalKeys.peer_topic/1`."
  defdelegate peer_topic(session_id), to: SignalKeys

  @doc "See `PriveeWeb.SignalKeys.maybe_notify_opk_low/2`."
  defdelegate maybe_notify_opk_low(session_id, remaining), to: SignalKeys

  # Event hook

  defp handle_event(event, params, socket) do
    if event in SignalKeys.events() do
      session_id = socket.assigns.current_session.id

      case SignalKeys.run(event, session_id, params) do
        {:ok, reply, :unchanged} ->
          {:halt, reply, socket}

        {:ok, reply, identity_key} ->
          {:halt, reply, assign(socket, :signal_identity_key, identity_key)}

        {:error, reason} ->
          Logger.debug("Signal key event #{event} failed: #{inspect(reason)}")
          {:halt, %{error: to_string(reason)}, socket}
      end
    else
      {:cont, socket}
    end
  end

  # Info hook

  defp handle_info(%{event: event} = message, socket) do
    cond do
      event == SignalKeys.opk_low_event() ->
        {:halt, push_event(socket, "replenish_prekeys", %{})}

      event == SignalKeys.identity_reset_event() ->
        key = message.payload.identity_key

        {:halt,
         socket
         |> assign(:signal_identity_key, key)
         |> push_event("identity_superseded", %{identity_key: key})}

      true ->
        {:cont, socket}
    end
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
