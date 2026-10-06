defmodule PriveeWeb.SessionShareController do
  @moduledoc """
  Controller for handling shared session links.

  This controller handles incoming requests to /share/:session_name and:
  - If user is already authenticated, redirects to chat with the specified session
  - If user is not authenticated, creates a quick session and logs them in automatically
  """

  use PriveeWeb, :controller

  alias Privee.Sessions
  alias PriveeWeb.SessionAuth

  @doc """
  Handles shared session links.

  If a session is already authenticated:
  - Validates the target session exists
  - Redirects to chat with the target session

  If no session is authenticated:
  - Generates a new quick session
  - Logs in the user automatically
  - Sets session return path to chat with target session
  """
  def share(conn, %{"session_name" => target_session_name}) do
    conn = SessionAuth.fetch_current_session(conn, [])

    case conn.assigns[:current_session] do
      %Sessions.Session{} = _current_session ->
        redirect_to_chat_if_session_exists(conn, target_session_name)

      nil ->
        create_quick_session_and_redirect(conn, target_session_name)
    end
  end

  defp redirect_to_chat_if_session_exists(conn, target_session_name) do
    case Sessions.get_session_by_session_name(target_session_name) do
      %Sessions.Session{} ->
        conn
        |> redirect(to: ~p"/chat/#{target_session_name}")

      nil ->
        conn
        |> put_flash(:error, "The session you're trying to join doesn't exist.")
        |> redirect(to: ~p"/privee")
    end
  end

  defp create_quick_session_and_redirect(conn, target_session_name) do
    case Sessions.get_session_by_session_name(target_session_name) do
      %Sessions.Session{} ->
        conn
        |> redirect(to: ~p"/?code=#{target_session_name}")

      nil ->
        conn
        |> put_flash(:error, "The session you're trying to join doesn't exist.")
        |> redirect(to: ~p"/")
    end
  end
end
