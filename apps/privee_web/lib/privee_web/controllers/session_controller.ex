defmodule PriveeWeb.SessionController do
  use PriveeWeb, :controller

  alias Privee.Sessions
  alias PriveeWeb.SessionAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"session" => session_params}, info) do
    %{"session_name" => session_name, "recovery_phrase" => recovery_phrase} = session_params

    if session = Sessions.get_session_by_session_name_and_phrase(session_name, recovery_phrase) do
      conn
      |> put_flash(:info, info)
      |> SessionAuth.log_in_session(session, session_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the recovery_phrase is registered.
      conn
      |> put_flash(:error, "Invalid recovery_phrase or session_name")
      |> put_flash(:recovery_phrase, String.slice(recovery_phrase, 0, 160))
      |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> SessionAuth.log_out_session()
  end
end
