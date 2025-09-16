defmodule PriveeWeb.SessionLoginLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Log in"
      assert html =~ "Create"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/")
        |> follow_redirect(conn, "/privee")

      assert {:ok, _conn} = result
    end
  end

  describe "session login" do
    test "redirects if session login with valid credentials", %{conn: conn} do
      recovery_phrase = session_recovery_phrase()
      session_name = unique_session_name()
      _session = session_fixture(%{session_name: session_name, recovery_phrase: recovery_phrase})

      {:ok, lv, _html} = live(conn, ~p"/login")

      form =
        form(lv, "#login_form",
          session: %{
            recovery_phrase: recovery_phrase,
            session_name: session_name,
            remember_me: true
          }
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/privee"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/login")

      form =
        form(lv, "#login_form",
          session: %{
            recovery_phrase: session_recovery_phrase(),
            session_name: "123456",
            remember_me: true
          }
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid recovery_phrase or session_name"

      assert redirected_to(conn) == "/"
    end
  end

  describe "quick session validation" do
    test "renders login form and shows error for already used quick session", %{conn: conn} do
      # Create a quick session and mark it as logged
      quick_session =
        quick_session_fixture(%{
          session_name: generate_new_unique_session_name(),
          has_logged: false
        })

      {:ok, logged_session} = Privee.Sessions.mark_session_as_logged(quick_session)

      {:ok, lv, _html} = live(conn, ~p"/login")

      # Test that the login form renders properly
      assert render(lv) =~ "Sign in to existing session"
      assert render(lv) =~ "Session Name"
      assert render(lv) =~ "Recovery phrase"

      # Since quick sessions don't have recovery phrases, they would fail through normal login
      form =
        form(lv, "#login_form",
          session: %{
            session_name: logged_session.session_name,
            recovery_phrase: ""
          }
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid recovery_phrase or session_name"

      assert redirected_to(conn) == "/"
    end

    test "validates quick session behavior through POST endpoint", %{conn: conn} do
      # Create a fresh quick session
      quick_session =
        quick_session_fixture(%{
          session_name: generate_new_unique_session_name(),
          has_logged: false
        })

      # Test that fresh quick session can login via POST (bypassing LiveView)
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{
            "session_name" => quick_session.session_name,
            "is_quick" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/privee"

      # Verify session is marked as logged
      updated_session = Privee.Sessions.get_session!(quick_session.id)
      assert updated_session.has_logged == true

      # Now test that the same session cannot login again
      conn =
        build_conn()
        |> post(~p"/sessions/log_in", %{
          "session" => %{
            "session_name" => updated_session.session_name,
            "is_quick" => "true"
          }
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid recovery_phrase or session_name"

      assert redirected_to(conn) == "/"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Create a new one")
        |> render_click()
        |> follow_redirect(conn, ~p"/")

      assert login_html =~ "Create"
    end
  end
end
