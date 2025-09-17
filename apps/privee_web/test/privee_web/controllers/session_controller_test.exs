defmodule PriveeWeb.SessionControllerTest do
  use PriveeWeb.ConnCase, async: true

  import Privee.SessionsFixtures

  setup do
    %{session: session_fixture()}
  end

  describe "POST /sessions/log_in" do
    test "logs the session in", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{
            "recovery_phrase" => session_recovery_phrase(),
            "session_name" => session.session_name
          }
        })

      assert get_session(conn, :session_token)
      assert redirected_to(conn) == ~p"/privee"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/privee")
      response = html_response(conn, 200)
      assert response =~ unique_session_name()
      assert response =~ ~p"/sessions/log_out"
    end

    test "logs the session in with remember me", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{
            "recovery_phrase" => session_recovery_phrase(),
            "session_name" => session.session_name,
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_privee_web_session_remember_me"]
      assert redirected_to(conn) == ~p"/privee"
    end

    test "logs the session in with return to", %{conn: conn, session: session} do
      conn =
        conn
        |> init_test_session(session_return_to: "/foo/bar")
        |> post(~p"/sessions/log_in", %{
          "session" => %{
            "recovery_phrase" => session_recovery_phrase(),
            "session_name" => session.session_name
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
            "recovery_phrase" => session_recovery_phrase(),
            "session_name" => session.session_name
          }
        })

      assert redirected_to(conn) == ~p"/privee"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Session created successfully"
    end

    # #19 - Use this test when the username will be available.
    # test "login following session_name update", %{conn: conn, session: session} do
    #   conn =
    #     conn
    #     |> post(~p"/sessions/log_in", %{
    #       "_action" => "session_name_updated",
    #       "session" => %{
    #         "recovery_phrase" => session.recovery_phrase,
    #         "session_name" => unique_session_name()
    #       }
    #     })

    #   assert redirected_to(conn) == ~p"/sessions/settings"
    #   assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "session_name updated successfully"
    # end

    test "redirects to login page with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/sessions/log_in", %{
          "session" => %{
            "recovery_phrase" => "invalid@recovery_phrase.com",
            "session_name" => "invalid_session_name"
          }
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Invalid recovery_phrase or session_name"

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to target session chat when target_session_code is provided", %{conn: conn} do
      # Create a quick session to use as the current session
      quick_session = quick_session_fixture(%{session_name: generate_new_unique_session_name()})
      # Create a target session to join
      target_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      conn =
        post(conn, ~p"/sessions/log_in", %{
          "_action" => "registered",
          "session" => %{
            "session_name" => quick_session.session_name,
            "is_quick" => "true"
          },
          "target_session_code" => target_session.session_name
        })

      # Should redirect to the target session chat
      assert redirected_to(conn) == ~p"/chat/#{target_session.session_name}"
      # Should be logged in
      assert get_session(conn, :session_token)
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
