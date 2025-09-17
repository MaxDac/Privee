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
            "session_name" => "too_short",
            "is_quick" => "false"
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
      valid_form_attributes = valid_session_attributes(session_name: session_name)

      form =
        form(lv, "#registration_form", session: Map.delete(valid_form_attributes, :public_key))

      # Applying the hidden input value in the submit, as the `form` function is intended
      # to simulate the user interaction only, and hidden inputs cannot be changed by the user.
      # Please refer to [this](https://github.com/phoenixframework/phoenix_live_view/issues/988#issuecomment-646586166)
      # and [this documentation](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html#render_submit/2)
      # highlighted from [this](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html#render_submit/2).
      render_submit(form, %{"session" => %{"public_key" => valid_form_attributes.public_key}})

      # This asserts that the session creation results in the copy to event being triggered
      assert_push_event(lv, "handle_new_session_registration", %{session_name: ^session_name})

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

  describe "quick session registration" do
    test "renders form with quick session toggle", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      session_name = generate_new_unique_session_name()

      # Test that the form renders the quick session toggle
      result =
        lv
        |> element("#registration_form")
        |> render_change(
          session: %{
            "session_name" => session_name,
            "is_quick" => "true"
          }
        )

      # When is_quick is true, recovery phrase field should be hidden
      refute result =~ "Recovery phrase"
      # Check for the actual toggle element that should be present
      assert result =~ "session[is_quick]"
    end

    test "renders form with recovery phrase when quick session is disabled", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      session_name = generate_new_unique_session_name()

      # Test that the form renders recovery phrase when quick session is disabled
      result =
        lv
        |> element("#registration_form")
        |> render_change(
          session: %{
            "session_name" => session_name,
            "is_quick" => "false"
          }
        )

      # When is_quick is false, recovery phrase field should be visible
      assert result =~ "Recovery phrase"
      assert result =~ "session[is_quick]"
    end

    test "validates that quick session workflow can be completed through LiveView user interaction",
         %{
           conn: conn
         } do
      {:ok, lv, _html} = live(conn, ~p"/")

      session_name = generate_new_unique_session_name()

      # Simulate user interaction: set session name and enable quick session toggle
      lv
      |> element("#registration_form")
      |> render_change(
        session: %{
          "session_name" => session_name,
          "is_quick" => "true"
        }
      )

      # Create form and submit it as a user would
      form =
        form(lv, "#registration_form",
          session: %{
            "session_name" => session_name,
            "is_quick" => "true"
          }
        )

      # Submit the form with public key (simulating the hidden field behavior)
      render_submit(form, %{"session" => %{"public_key" => generate_new_unique_public_key()}})

      # Verify the session creation event was triggered
      assert_push_event(lv, "handle_new_session_registration", %{session_name: ^session_name})

      # Follow the trigger action as the browser would
      conn = follow_trigger_action(form, conn)

      # Verify successful login redirect
      assert redirected_to(conn) == ~p"/privee"

      # Verify the session was created with correct properties and marked as logged
      created_session = Privee.Sessions.get_session_by_session_name(session_name)
      assert created_session.is_quick == true
      assert created_session.has_logged == true

      # Verify user can access the protected page
      conn = get(conn, "/privee")
      response = html_response(conn, 200)
      assert response =~ "Session"
    end

    test "auto-enables quick session toggle when code parameter is present", %{conn: conn} do
      target_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      {:ok, _lv, html} = live(conn, "/?code=#{target_session.session_name}")

      # The is_quick toggle should be automatically enabled
      assert html =~ "checked=\"\""
      # The form should include the target_session_code as a hidden field
      assert html =~ "name=\"target_session_code\""
      assert html =~ "value=\"#{target_session.session_name}\""

      # When code is present, recovery phrase field should be hidden
      refute html =~ "Recovery phrase"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign in")
        |> render_click()
        |> follow_redirect(conn, ~p"/")

      assert login_html =~ "Log in"
    end
  end
end
