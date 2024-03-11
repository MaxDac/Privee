defmodule PriveeWeb.SessionForgotPasswordLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  alias Privee.Sessions
  alias Privee.Repo

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/sessions/reset_password")

      assert html =~ "Forgot your password?"
      assert has_element?(lv, ~s|a[href="#{~p"/sessions/register"}"]|, "Register")
      assert has_element?(lv, ~s|a[href="#{~p"/sessions/log_in"}"]|, "Log in")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/sessions/reset_password")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    setup do
      %{session: session_fixture()}
    end

    test "sends a new reset password token", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", session: %{"email" => session.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"

      assert Repo.get_by!(Sessions.SessionToken, session_id: session.id).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", session: %{"email" => "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Repo.all(Sessions.SessionToken) == []
    end
  end
end
