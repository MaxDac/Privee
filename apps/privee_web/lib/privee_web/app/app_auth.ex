defmodule PriveeWeb.App.AppAuth do
  @moduledoc """
  Bearer-token authentication for the native app.

  The app authenticates HTTP requests with `Authorization: Bearer <token>` and
  the `PriveeWeb.App.AppSocket` with the Phoenix channels `auth_token`. The token
  is the session token (see `Privee.Sessions.generate_session_token/1`) encoded
  as unpadded base64url.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Privee.Sessions

  @doc "Encodes a raw session token for the app."
  def encode_token(token) when is_binary(token), do: Base.url_encode64(token, padding: false)

  @doc "Decodes a token encoded with `encode_token/1`."
  def decode_token(encoded) when is_binary(encoded),
    do: Base.url_decode64(encoded, padding: false)

  def decode_token(_encoded), do: :error

  @doc "Returns the session and the raw token authenticated by the encoded token."
  def authenticate(encoded) do
    with {:ok, token} <- decode_token(encoded),
         session when not is_nil(session) <- Sessions.get_session_by_session_token(token) do
      {:ok, session, token}
    else
      _ -> :error
    end
  end

  @doc """
  Id of the app sockets authenticated by the raw `token`, used to disconnect
  them on log out. Derived from a hash so the token itself is never broadcast.
  """
  def socket_id(token) do
    "app_socket:" <> Base.url_encode64(:crypto.hash(:sha256, token), padding: false)
  end

  @doc """
  Plug assigning `:current_session` and `:app_token` from the bearer token, or
  halting with `401`.
  """
  def require_app_session(conn, _opts) do
    with ["Bearer " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, session, token} <- authenticate(String.trim(encoded)) do
      conn
      |> assign(:current_session, session)
      |> assign(:app_token, token)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end
end
