defmodule PriveeWeb.SessionAuth do
  @moduledoc """
  This module provides functions that manage the session,
  """

  use PriveeWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Privee.Sessions

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in SessionToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_privee_web_session_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the session in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_session(conn, session, params \\ %{}) do
    token = Sessions.generate_session_token(session)
    session_return_to = get_session(conn, :session_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: session_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the session out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_session(conn) do
    session_token = get_session(conn, :session_token)
    session_token && Sessions.delete_session_token(session_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      PriveeWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the session by looking into the session
  and remember me token.
  """
  def fetch_current_session(conn, _opts) do
    {session_token, conn} = ensure_session_token(conn)
    session = session_token && Sessions.get_session_by_session_token(session_token)
    assign(conn, :current_session, session)
  end

  defp ensure_session_token(conn) do
    if token = get_session(conn, :session_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_session in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_session` - Assigns current_session
      to socket assigns based on session_token, or nil if
      there's no session_token or no matching session.

    * `:ensure_authenticated` - Authenticates the session from the session,
      and assigns the current_session to socket assigns based
      on session_token.
      Redirects to login page if there's no logged session.

    * `:redirect_if_session_is_authenticated` - Authenticates the session from the session.
      Redirects to signed_in_path if there's a logged session.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_session:

      defmodule PriveeWeb.PageLive do
        use PriveeWeb, :live_viewYou must have a session to access this page

        on_mount {PriveeWeb.SessionAuth, :mount_current_session}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{PriveeWeb.SessionAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_session, _params, session, socket) do
    {:cont, mount_current_session(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_session(socket, session)

    if socket.assigns.current_session do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must have a session to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_session_is_authenticated, _params, session, socket) do
    socket = mount_current_session(socket, session)

    if socket.assigns.current_session do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_session(socket, session) do
    Phoenix.Component.assign_new(socket, :current_session, fn ->
      if session_token = session["session_token"],
        do: Sessions.get_session_by_session_token(session_token)
    end)
  end

  @doc """
  Used for routes that require the session to not be authenticated.
  """
  def redirect_if_session_is_authenticated(conn, _opts) do
    if conn.assigns[:current_session] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the session to be authenticated.

  If you want to enforce the session email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_session(conn, _opts) do
    if conn.assigns[:current_session] do
      conn
    else
      conn
      |> put_flash(:error, "You must have a session to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:session_token, token)
    |> put_session(:live_socket_id, "sessions_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :session_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/privee"
end
