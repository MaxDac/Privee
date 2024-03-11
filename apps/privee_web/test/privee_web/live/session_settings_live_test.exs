defmodule PriveeWeb.SessionSettingsLiveTest do
  use PriveeWeb.ConnCase, async: true

  alias Privee.Sessions
  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/sessions/settings")

      assert html =~ "Change Email"
      assert html =~ "Change Password"
    end

    test "redirects if session is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/sessions/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/sessions/log_in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      password = valid_session_password()
      session = session_fixture(%{password: password})
      %{conn: log_in_session(conn, session), session: session, password: password}
    end

    test "updates the session email", %{conn: conn, password: password, session: session} do
      new_email = unique_session_email()

      {:ok, lv, _html} = live(conn, ~p"/sessions/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => password,
          "session" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Sessions.get_session_by_email(session.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "current_password" => "invalid",
          "session" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/settings")

      result =
        lv
        |> form("#email_form", %{
          "current_password" => "invalid",
          "session" => %{"email" => session.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
      assert result =~ "is not valid"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      password = valid_session_password()
      session = session_fixture(%{password: password})
      %{conn: log_in_session(conn, session), session: session, password: password}
    end

    test "updates the session password", %{conn: conn, session: session, password: password} do
      new_password = valid_session_password()

      {:ok, lv, _html} = live(conn, ~p"/sessions/settings")

      form =
        form(lv, "#password_form", %{
          "current_password" => password,
          "session" => %{
            "email" => session.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/sessions/settings"

      assert get_session(new_password_conn, :session_token) != get_session(conn, :session_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Sessions.get_session_by_email_and_password(session.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "current_password" => "invalid",
          "session" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Change Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/settings")

      result =
        lv
        |> form("#password_form", %{
          "current_password" => "invalid",
          "session" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Change Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
      assert result =~ "is not valid"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      session = session_fixture()
      email = unique_session_email()

      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_update_email_instructions(%{session | email: email}, session.email, url)
        end)

      %{conn: log_in_session(conn, session), token: token, email: email, session: session}
    end

    test "updates the session email once", %{conn: conn, session: session, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/sessions/settings/confirm_email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/sessions/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Sessions.get_session_by_email(session.email)
      assert Sessions.get_session_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/sessions/settings/confirm_email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/sessions/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, session: session} do
      {:error, redirect} = live(conn, ~p"/sessions/settings/confirm_email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/sessions/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Sessions.get_session_by_email(session.email)
    end

    test "redirects if session is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/sessions/settings/confirm_email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/sessions/log_in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
