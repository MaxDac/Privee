defmodule PriveeWeb.SessionConfirmationInstructionsLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  alias Privee.Sessions
  alias Privee.Repo

  setup do
    %{session: session_fixture()}
  end

  describe "Resend confirmation" do
    test "renders the resend confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sessions/confirm")
      assert html =~ "Resend confirmation instructions"
    end

    test "sends a new confirmation token", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", session: %{email: session.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Sessions.SessionToken, session_id: session.id).context == "confirm"
    end

    test "does not send confirmation token if session is confirmed", %{conn: conn, session: session} do
      Repo.update!(Sessions.Session.confirm_changeset(session))

      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", session: %{email: session.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      refute Repo.get_by(Sessions.SessionToken, session_id: session.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm")

      {:ok, conn} =
        lv
        |> form("#resend_confirmation_form", session: %{email: "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.all(Sessions.SessionToken) == []
    end
  end
end
