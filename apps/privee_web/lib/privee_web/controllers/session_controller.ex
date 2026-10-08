defmodule PriveeWeb.SessionController do
  use PriveeWeb, :controller

  alias Privee.Sessions
  alias PriveeWeb.SessionAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(
      conn,
      params,
      gettext(
        "Session created successfully! Your session name has been automatically copied to the clipboard."
      )
    )
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back!"))
  end

  defp create(conn, %{"session" => session_params} = params, info) do
    with session when not is_nil(session) <- get_session_from_params(session_params),
         true <- Sessions.session_valid?(session),
         {:ok, session} <- Sessions.mark_session_as_logged(session) do
      conn
      |> maybe_set_session_return_to(params)
      |> put_flash(:info, info)
      |> SessionAuth.log_in_session(session, session_params)
    else
      _ ->
        conn
        |> put_error_flash(session_params)
    end
  end

  defp maybe_set_session_return_to(conn, params) do
    case params["target_session_code"] do
      nil ->
        conn

      target_session_code ->
        put_session(conn, :session_return_to, ~p"/chat/#{target_session_code}")
    end
  end

  defp put_error_flash(conn, _session_params) do
    # In order to prevent user enumeration attacks, don't disclose whether the recovery_phrase is registered.
    conn
    |> put_flash(:error, gettext("Invalid recovery phrase or session name"))
    |> redirect(to: ~p"/")
  end

  defp get_session_from_params(session_params) do
    case session_params do
      %{"session_name" => session_name, "recovery_phrase" => recovery_phrase} ->
        Sessions.get_session_by_session_name_and_phrase(session_name, recovery_phrase)

      %{"session_name" => session_name, "is_quick" => "true"} ->
        Sessions.get_session_by_session_name(session_name)

      _ ->
        nil
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> SessionAuth.log_out_session()
  end
end
