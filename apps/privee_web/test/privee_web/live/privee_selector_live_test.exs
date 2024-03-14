defmodule PriveeWeb.PriveeSelectorLiveTest do
  @moduledoc """
  Tests for the privee selector live view.
  """

  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  describe "privee_selector_live" do
    test " renders the privee selector view when the user is logged in", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/privee")

      assert html =~ "Create a new Privée"
    end

    test " redirects to the login when the user is not logged in", %{conn: conn} do
      result =
        conn
        |> live(~p"/privee")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test " shows an error when selecting an invalid session name", %{conn: conn} do
      %{session_name: session_name} = session = session_fixture()

      {:ok, privee_selector_live, _html} =
        conn
        |> log_in_session(session)
        |> live(~p"/privee")

      result =
        privee_selector_live
        |> form("#privee_form", %{privee_form: %{session_name: session_name}})
        |> render_change()

      assert result =~ "You selected your session name"

      result =
        privee_selector_live
        |> form("#privee_form", %{privee_form: %{session_name: "invalid session name"}})
        |> render_change()

      assert result =~ "must contain only alphanumeric characters and hyphens"

      result =
        privee_selector_live
        |> form("#privee_form", %{
          privee_form: %{session_name: "non-existent-but-valid-session-name"}
        })
        |> render_change()

      assert result =~ "The session name does not exist"
    end

    test " shows an error when submitting an invalid session name", %{conn: conn} do
      %{session_name: session_name} = session = session_fixture()

      {:ok, privee_selector_live, _html} =
        conn
        |> log_in_session(session)
        |> live(~p"/privee")

      result =
        privee_selector_live
        |> form("#privee_form", %{privee_form: %{session_name: session_name}})
        |> render_submit()

      assert result =~ "You selected your session name"

      result =
        privee_selector_live
        |> form("#privee_form", %{privee_form: %{session_name: "invalid session name"}})
        |> render_submit()

      assert result =~ "must contain only alphanumeric characters and hyphens"

      result =
        privee_selector_live
        |> form("#privee_form", %{
          privee_form: %{session_name: "non-existent-but-valid-session-name"}
        })
        |> render_submit()

      assert result =~ "The session name does not exist"
    end

    test " redirect to the chat when the right session name has been selected", %{conn: conn} do
      session = session_fixture()

      %{session_name: session_name} =
        session_fixture(%{
          session_name: "another-twenty-four-session-name",
          recovery_phrase: "Yet another recovery phrase of more than twenty four characters"
        })

      conn = log_in_session(conn, session)

      {:ok, privee_selector_live, _html} =
        conn
        |> live(~p"/privee")

      {:ok, _chat_live_view, html} =
        privee_selector_live
        |> form("#privee_form", %{privee_form: %{session_name: session_name}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/chat/#{session_name}")

      assert html =~ "#{session_name}"
    end
  end
end
