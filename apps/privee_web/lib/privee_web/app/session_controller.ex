defmodule PriveeWeb.App.SessionController do
  @moduledoc """
  JSON API used by the native app to create, log into and log out of sessions.

    * `POST /api/app/sessions` - registers a session (`recovery_phrase`, or
      `is_quick: true`; `session_name` is generated when missing) and logs in.
    * `POST /api/app/sessions/log_in` - `session_name` with `recovery_phrase`, or
      with `is_quick: true` for a quick session that has never been logged into.
    * `GET /api/app/session` - the authenticated session.
    * `DELETE /api/app/session` - logs out, revoking the token.

  Successful log ins return `%{token, session: %{session_name, is_quick}}`; the
  token authenticates later requests (`Authorization: Bearer <token>`) and the
  app socket. Failed log ins never disclose which credential was wrong.
  """

  use PriveeWeb, :controller

  alias Privee.RateLimiter
  alias Privee.SessionNameProvider
  alias Privee.Sessions
  alias PriveeWeb.App.AppAuth
  alias PriveeWeb.Endpoint

  @auth_attempts_per_window 10
  @auth_window_ms :timer.minutes(1)

  plug :rate_limit when action in [:register, :log_in]

  def register(conn, params) do
    attrs = %{
      "session_name" => params["session_name"] || generate_session_name(),
      "recovery_phrase" => params["recovery_phrase"],
      "is_quick" => params["is_quick"] == true or params["is_quick"] == "true"
    }

    case Sessions.register_session(attrs) do
      {:ok, session} ->
        conn
        |> put_status(:created)
        |> log_in_session(session)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", errors: errors_on(changeset)})
    end
  end

  def log_in(conn, params) do
    with session when not is_nil(session) <- find_session(params),
         true <- Sessions.session_valid?(session) do
      log_in_session(conn, session)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})
    end
  end

  def show(conn, _params),
    do: json(conn, %{session: render_session(conn.assigns.current_session)})

  def delete(conn, _params) do
    token = conn.assigns.app_token
    Sessions.delete_session_token(token)
    Endpoint.broadcast(AppAuth.socket_id(token), "disconnect", %{})
    send_resp(conn, :no_content, "")
  end

  defp log_in_session(conn, session) do
    {:ok, session} = Sessions.mark_session_as_logged(session)
    token = Sessions.generate_session_token(session)
    json(conn, %{token: AppAuth.encode_token(token), session: render_session(session)})
  end

  defp find_session(%{"session_name" => name, "recovery_phrase" => phrase})
       when is_binary(name) and is_binary(phrase),
       do: Sessions.get_session_by_session_name_and_phrase(name, phrase)

  defp find_session(%{"session_name" => name, "is_quick" => quick})
       when is_binary(name) and quick in [true, "true"] do
    case Sessions.get_session_by_session_name(name) do
      %{is_quick: true} = session -> session
      _ -> nil
    end
  end

  defp find_session(_params), do: nil

  defp generate_session_name do
    {:ok, name} = SessionNameProvider.generate_new_available_session_name()
    name
  end

  defp render_session(session),
    do: %{session_name: session.session_name, is_quick: session.is_quick}

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp rate_limit(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case RateLimiter.hit({:app_auth, ip}, @auth_attempts_per_window, @auth_window_ms) do
      :ok ->
        conn

      :limited ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limited"})
        |> halt()
    end
  end
end
