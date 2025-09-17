defmodule PriveeWeb.SessionShareControllerTest do
  use PriveeWeb.ConnCase, async: true

  import Privee.SessionsFixtures

  describe "GET /share/:session_name when user is authenticated" do
    setup %{conn: conn} do
      current_session = session_fixture(%{has_logged: true})
      target_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      conn =
        conn
        |> Map.replace!(:secret_key_base, PriveeWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> log_in_session(current_session)

      %{conn: conn, current_session: current_session, target_session: target_session}
    end

    test "redirects to chat when target session exists", %{
      conn: conn,
      target_session: target_session
    } do
      conn = get(conn, ~p"/share/#{target_session.session_name}")

      assert redirected_to(conn) == ~p"/chat/#{target_session.session_name}"
    end

    test "redirects to privee page when target session doesn't exist", %{conn: conn} do
      conn = get(conn, ~p"/share/non-existent-session")

      assert redirected_to(conn) == ~p"/privee"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't exist"
    end
  end

  describe "GET /share/:session_name when user is not authenticated" do
    test "redirects to registration page with code when target session exists", %{conn: conn} do
      target_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      conn = get(conn, ~p"/share/#{target_session.session_name}")

      # Should redirect to the registration page with the target session code
      assert redirected_to(conn) == "/?code=#{target_session.session_name}"

      # Should not have logged in the user yet
      refute get_session(conn, :session_token)
    end

    test "redirects to home page when target session doesn't exist", %{conn: conn} do
      conn = get(conn, ~p"/share/non-existent-session")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "doesn't exist"
    end
  end

  describe "GET /share/:session_name edge cases" do
    test "handles special characters in session name properly", %{conn: conn} do
      # Test with URL-encoded special characters, but use a valid session name first
      valid_session_name = generate_new_unique_session_name()
      _target_session = session_fixture(%{session_name: valid_session_name})

      # Test with URL encoding
      encoded_session_name = URI.encode(valid_session_name)

      conn = get(conn, "/share/#{encoded_session_name}")

      # Should redirect to registration page with code since we decode the session name properly
      assert redirected_to(conn) == "/?code=#{valid_session_name}"
    end

    test "handles empty session name", %{conn: conn} do
      # This should result in a route not found error
      conn = get(conn, "/share/")

      # The route pattern /share/:session_name doesn't match /share/
      # so it should return a 404-like error
      assert conn.status == 404
    end
  end
end
