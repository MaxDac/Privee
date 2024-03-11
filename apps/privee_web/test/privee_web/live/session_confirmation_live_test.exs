defmodule PriveeWeb.SessionConfirmationLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  alias Privee.Sessions
  alias Privee.Repo

  setup do
    %{session: session_fixture()}
  end

  describe "Confirm session" do
    test "renders confirmation page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sessions/confirm/some-token")
      assert html =~ "Confirm Account"
    end

    test "confirms the given token once", %{conn: conn, session: session} do
      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_confirmation_instructions(session, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Session confirmed successfully"

      assert Sessions.get_session!(session.id).confirmed_at
      refute get_session(conn, :session_token)
      assert Repo.all(Sessions.SessionToken) == []

      # when not logged in
      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Session confirmation link is invalid or it has expired"

      # when logged in
      conn =
        build_conn()
        |> log_in_session(session)

      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm/#{token}")

      result =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert {:ok, conn} = result
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, session: session} do
      {:ok, lv, _html} = live(conn, ~p"/sessions/confirm/invalid-token")

      {:ok, conn} =
        lv
        |> form("#confirmation_form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Session confirmation link is invalid or it has expired"

      refute Sessions.get_session!(session.id).confirmed_at
    end
  end
end
