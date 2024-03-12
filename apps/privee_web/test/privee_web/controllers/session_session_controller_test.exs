defmodule PriveeWeb.SessionSessionControllerTest do
  use PriveeWeb.ConnCase, async: true

  import Privee.SessionsFixtures

  setup do
    %{session: session_fixture()}
  end

  describe "POST /sessions/log_in" do
    test "logs the session in", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{"email" => session.email, "password" => valid_session_password()}
        })

      assert get_session(conn, :session_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ session.email
      assert response =~ ~p"/sessions/settings"
      assert response =~ ~p"/sessions/log_out"
    end

    test "logs the session in with remember me", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{
            "email" => session.email,
            "password" => valid_session_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_privee_web_session_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the session in with return to", %{conn: conn, session: session} do
      conn =
        conn
        |> init_test_session(session_return_to: "/foo/bar")
        |> post(~p"/sessions/log_in", %{
          "session" => %{
            "email" => session.email,
            "password" => valid_session_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "login following registration", %{conn: conn, session: session} do
      conn =
        conn
        |> post(~p"/sessions/log_in", %{
          "_action" => "registered",
          "session" => %{
            "email" => session.email,
            "password" => valid_session_password()
          }
        })

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Account created successfully"
    end

    test "login following password update", %{conn: conn, session: session} do
      conn =
        conn
        |> post(~p"/sessions/log_in", %{
          "_action" => "password_updated",
          "session" => %{
            "email" => session.email,
            "password" => valid_session_password()
          }
        })

      assert redirected_to(conn) == ~p"/sessions/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
    end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{"email" => "invalid@email.com", "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "DELETE /sessions/log_out" do
    test "logs the session out", %{conn: conn, session: session} do
      conn = conn |> log_in_session(session) |> delete(~p"/sessions/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :session_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the session is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/sessions/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :session_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
