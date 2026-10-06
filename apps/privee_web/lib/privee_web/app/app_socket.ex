defmodule PriveeWeb.App.AppSocket do
  @moduledoc """
  Channels socket for the native app, mounted at `/app/socket`.

  Authenticated with the session token through the Phoenix channels
  `auth_token` (sent in the `Sec-WebSocket-Protocol` header as
  `base64url.bearer.phx.<unpadded base64 of the app token>`).

  Channels:

    * `session` - key management (`PriveeWeb.App.SessionChannel`)
    * `chat:<peer session name>` - a privee (`PriveeWeb.App.ChatChannel`)
  """

  use Phoenix.Socket

  alias PriveeWeb.App.AppAuth

  channel "session", PriveeWeb.App.SessionChannel
  channel "chat:*", PriveeWeb.App.ChatChannel

  @impl true
  def connect(_params, socket, %{auth_token: encoded}) when is_binary(encoded) do
    case AppAuth.authenticate(encoded) do
      {:ok, session, token} ->
        {:ok,
         socket
         |> assign(:current_session, session)
         |> assign(:socket_id, AppAuth.socket_id(token))}

      :error ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: socket.assigns.socket_id
end
