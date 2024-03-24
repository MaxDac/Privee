defmodule PriveeWeb.SessionRegistrationLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  alias Privee.SessionNameProvider.Test

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Create"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/")
        |> follow_redirect(conn, "/privee")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          session: %{
            "recovery_phrase" => "with !@# special characters but long enough",
            "session_name" => "too_short"
          }
        )

      assert result =~ "Create"
      assert result =~ "must contain only alphabetic characters and punctuation"
      assert result =~ "should be at least 24 character"
    end
  end

  describe "register session" do
    test "creates account and logs the session in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      session_name = unique_session_name()

      form =
        form(lv, "#registration_form",
          session: valid_session_attributes(session_name: session_name)
        )

      render_submit(form)

      # This asserts that the session creation results in the copy to event being triggered
      assert_push_event(lv, "copy_to_clipboard", %{session_name: ^session_name})

      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/privee"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/privee")
      response = html_response(conn, 200)
      assert response =~ "Session"
    end

    test "creates account and even though the user does not specify the session name", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/")
      mocked_session_name = Test.get_mocked_unique_session_name()

      session_name_input_element =
        lv
        |> element("#session_session_name")
        |> render()

      assert session_name_input_element =~ "value=\"#{mocked_session_name}\""
    end

    test "renders errors for duplicated session name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      _session = session_fixture(%{session_name: unique_session_name()})

      result =
        lv
        |> form("#registration_form",
          session: %{
            "recovery_phrase" => session_recovery_phrase(),
            "session_name" => unique_session_name()
          }
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      {:ok, _login_live, login_html} =
        lv
        |> element(~s|main a:fl-contains("Sign in")|)
        |> render_click()
        |> follow_redirect(conn, ~p"/")

      assert login_html =~ "Log in"
    end
  end
end
