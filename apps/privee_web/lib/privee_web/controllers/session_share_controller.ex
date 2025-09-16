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
        case create_and_login_quick_session(conn, target_session_name) do
          {:ok, conn} -> conn
          {:error, conn} -> conn
        end

      nil ->
        conn
        |> put_flash(:error, "The session you're trying to join doesn't exist.")
        |> redirect(to: ~p"/")
    end
  end

  defp create_and_login_quick_session(conn, target_session_name) do
    with session_name <- Sessions.generate_new_available_session_name(),
         {:ok, session} <- create_quick_session(session_name),
         {:ok, session} <- Sessions.mark_session_as_logged(session) do
      conn =
        conn
        |> put_session(:session_return_to, ~p"/chat/#{target_session_name}")
        |> SessionAuth.log_in_session(session)

      {:ok, conn}
    else
      _ ->
        conn =
          conn
          |> put_flash(:error, "Unable to create a session. Please try again.")
          |> redirect(to: ~p"/")

        {:error, conn}
    end
  end

  defp create_quick_session(session_name) do
    # Generate a public key for the quick session (simplified for sharing purposes)
    public_key = generate_public_key()

    Sessions.register_session(%{
      session_name: session_name,
      public_key: public_key,
      is_quick: true
    })
  end

  # Generate a simple placeholder public key for quick sessions
  # In a real application, this would involve proper cryptographic key generation
  defp generate_public_key do
    # Using a UUID as a placeholder public key for quick sessions
    # This is simplified - in production you'd want proper key generation
    Ecto.UUID.generate()
  end
end
