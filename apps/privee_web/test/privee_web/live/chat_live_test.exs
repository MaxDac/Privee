defmodule PriveeWeb.ChatLiveTest do
  @moduledoc """
  Tests for the chat live.
  """

  use PriveeWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  describe "chat_live" do
    test " renders the chat view when the user is logged in", %{conn: conn} do
      {:ok, _lv, html} = 
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/chat")

      assert html =~ "Create a new Privée"
    end

    test " redirects to the login when the user is not logged in", %{conn: conn} do
      result = 
        conn
        |> live(~p"/chat")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test " shows an error when selecting an invalid session name", %{conn: conn} do
      %{session_name: session_name} = session = session_fixture()
      {:ok, chat_live, _html} = 
        conn
        |> log_in_session(session)
        |> live(~p"/chat")

      result =
        chat_live
        |> form("#privee_form", %{privee_form: %{session_name: session_name}})
        |> render_change()

      assert result =~ "You selected your session name"

      result =
        chat_live
        |> form("#privee_form", %{privee_form: %{session_name: "invalid session name"}})
        |> render_change()

      assert result =~ "must contain only alphanumeric characters and hyphens"

      result =
        chat_live
        |> form("#privee_form", %{privee_form: %{session_name: "non-existent-but-valid-session-name"}})
        |> render_change()

      assert result =~ "The session name does not exist"
    end

    test " shows an error when submitting an invalid session name", %{conn: conn} do
      %{session_name: session_name} = session = session_fixture()
      {:ok, chat_live, _html} = 
        conn
        |> log_in_session(session)
        |> live(~p"/chat")

      result =
        chat_live
        |> form("#privee_form", %{privee_form: %{session_name: session_name}})
        |> render_submit()

      assert result =~ "You selected your session name"

      result =
        chat_live
        |> form("#privee_form", %{privee_form: %{session_name: "invalid session name"}})
        |> render_submit()

      assert result =~ "must contain only alphanumeric characters and hyphens"

      result =
        chat_live
        |> form("#privee_form", %{privee_form: %{session_name: "non-existent-but-valid-session-name"}})
        |> render_submit()

      assert result =~ "The session name does not exist"
    end
  end
end
