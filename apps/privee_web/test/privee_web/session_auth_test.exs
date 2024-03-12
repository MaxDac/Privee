defmodule PriveeWeb.SessionAuthTest do
  use PriveeWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias Privee.Sessions
  alias PriveeWeb.SessionAuth
  import Privee.SessionsFixtures

  @remember_me_cookie "_privee_web_session_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, PriveeWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{session: session_fixture(), conn: conn}
  end

  describe "log_in_session/3" do
    test "stores the session token in the session", %{conn: conn, session: session} do
      conn = SessionAuth.log_in_session(conn, session)
      assert token = get_session(conn, :session_token)
      assert get_session(conn, :live_socket_id) == "sessions_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/chat"
      assert Sessions.get_session_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, session: session} do
      conn = conn |> put_session(:to_be_removed, "value") |> SessionAuth.log_in_session(session)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, session: session} do
      conn = conn |> put_session(:session_return_to, "/hello") |> SessionAuth.log_in_session(session)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, session: session} do
      conn = conn |> fetch_cookies() |> SessionAuth.log_in_session(session, %{"remember_me" => "true"})
      assert get_session(conn, :session_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :session_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_session/1" do
    test "erases session and cookies", %{conn: conn, session: session} do
      session_token = Sessions.generate_session_token(session)

      conn =
        conn
        |> put_session(:session_token, session_token)
        |> put_req_cookie(@remember_me_cookie, session_token)
        |> fetch_cookies()
        |> SessionAuth.log_out_session()

      refute get_session(conn, :session_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Sessions.get_session_by_session_token(session_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "sessions_sessions:abcdef-token"
      PriveeWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> SessionAuth.log_out_session()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if session is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> SessionAuth.log_out_session()
      refute get_session(conn, :session_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_session/2" do
    test "authenticates session from session", %{conn: conn, session: session} do
      session_token = Sessions.generate_session_token(session)
      conn = conn |> put_session(:session_token, session_token) |> SessionAuth.fetch_current_session([])
      assert conn.assigns.current_session.id == session.id
    end

    test "authenticates session from cookies", %{conn: conn, session: session} do
      logged_in_conn =
        conn |> fetch_cookies() |> SessionAuth.log_in_session(session, %{"remember_me" => "true"})

      session_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> SessionAuth.fetch_current_session([])

      assert conn.assigns.current_session.id == session.id
      assert get_session(conn, :session_token) == session_token

      assert get_session(conn, :live_socket_id) ==
               "sessions_sessions:#{Base.url_encode64(session_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, session: session} do
      _ = Sessions.generate_session_token(session)
      conn = SessionAuth.fetch_current_session(conn, [])
      refute get_session(conn, :session_token)
      refute conn.assigns.current_session
    end
  end

  describe "on_mount :mount_current_session" do
    test "assigns current_session based on a valid session_token", %{conn: conn, session: session} do
      IO.inspect(session.session_name, label: "session name")
      session_token = Sessions.generate_session_token(session)
      socket_session =
        conn
        |> put_session(:session_token, session_token)
        |> put_session(:session_name, unique_session_name())
        |> get_session()

      {:cont, updated_socket} =
        SessionAuth.on_mount(:mount_current_session, %{}, socket_session, %LiveView.Socket{})

      assert updated_socket.assigns.current_session.id == session.id
    end

    test "assigns nil to current_session assign if there isn't a valid session_token", %{conn: conn} do
      session_token = "invalid_token"
      session = conn |> put_session(:session_token, session_token) |> get_session()

      {:cont, updated_socket} =
        SessionAuth.on_mount(:mount_current_session, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_session == nil
    end

    test "assigns nil to current_session assign if there isn't a session_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        SessionAuth.on_mount(:mount_current_session, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_session == nil
    end
  end

  describe "on_mount :ensure_authenticated" do
    test "authenticates current_session based on a valid session_token", %{conn: conn, session: session} do
      session_token = Sessions.generate_session_token(session)
      session = conn |> put_session(:session_token, session_token) |> get_session()

      {:cont, updated_socket} =
        SessionAuth.on_mount(:ensure_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_session.id == session.id
    end

    test "redirects to login page if there isn't a valid session_token", %{conn: conn} do
      session_token = "invalid_token"
      session = conn |> put_session(:session_token, session_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: PriveeWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = SessionAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_session == nil
    end

    test "redirects to login page if there isn't a session_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: PriveeWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = SessionAuth.on_mount(:ensure_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_session == nil
    end
  end

  describe "on_mount :redirect_if_session_is_authenticated" do
    test "redirects if there is an authenticated  session ", %{conn: conn, session: session} do
      session_token = Sessions.generate_session_token(session)
      session =
        conn
        |> put_session(:session_token, session_token)
        |> put_session(:session_name, unique_session_name())
        |> get_session()

      assert {:halt, _updated_socket} =
               SessionAuth.on_mount(
                 :redirect_if_session_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end

    test "doesn't redirect if there is no authenticated session", %{conn: conn} do
      session = conn |> get_session()

      assert {:cont, _updated_socket} =
               SessionAuth.on_mount(
                 :redirect_if_session_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end
  end

  describe "redirect_if_session_is_authenticated/2" do
    test "redirects if session is authenticated", %{conn: conn, session: session} do
      conn = conn |> assign(:current_session, session) |> SessionAuth.redirect_if_session_is_authenticated([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/chat"
    end

    test "does not redirect if session is not authenticated", %{conn: conn} do
      conn = SessionAuth.redirect_if_session_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_session/2" do
    test "redirects if session is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> SessionAuth.require_authenticated_session([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> SessionAuth.require_authenticated_session([])

      assert halted_conn.halted
      assert get_session(halted_conn, :session_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> SessionAuth.require_authenticated_session([])

      assert halted_conn.halted
      assert get_session(halted_conn, :session_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> SessionAuth.require_authenticated_session([])

      assert halted_conn.halted
      refute get_session(halted_conn, :session_return_to)
    end

    test "does not redirect if session is authenticated", %{conn: conn, session: session} do
      conn = conn |> assign(:current_session, session) |> SessionAuth.require_authenticated_session([])
      refute conn.halted
      refute conn.status
    end
  end
end
