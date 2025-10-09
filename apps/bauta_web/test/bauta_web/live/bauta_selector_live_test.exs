defmodule BautaWeb.BautaSelectorLiveTest do
  @moduledoc """
  Tests for the bauta selector live view.
  """

  use BautaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bauta.SessionsFixtures

  describe "bauta_selector_live" do
    test " renders the bauta selector view when the user is logged in", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_session(session_fixture())
        |> live(~p"/bauta")

      assert html =~ "Create a new Privée"
    end

    test " redirects to the login when the user is not logged in", %{conn: conn} do
      result =
        conn
        |> live(~p"/bauta")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test " shows an error when selecting an invalid session name", %{conn: conn} do
      %{session_name: session_name} = session = session_fixture()

      {:ok, bauta_selector_live, _html} =
        conn
        |> log_in_session(session)
        |> live(~p"/bauta")

      result =
        bauta_selector_live
        |> form("#bauta_form", %{bauta_form: %{session_name: session_name}})
        |> render_change()

      assert result =~ "You selected your session name"

      result =
        bauta_selector_live
        |> form("#bauta_form", %{bauta_form: %{session_name: "invalid session name"}})
        |> render_change()

      assert result =~ "must contain only alphanumeric characters and hyphens"

      result =
        bauta_selector_live
        |> form("#bauta_form", %{
          bauta_form: %{session_name: "non-existent-but-valid-session-name"}
        })
        |> render_change()

      assert result =~ "The session name does not exist"
    end

    test " shows an error when submitting an invalid session name", %{conn: conn} do
      %{session_name: session_name} = session = session_fixture()

      {:ok, bauta_selector_live, _html} =
        conn
        |> log_in_session(session)
        |> live(~p"/bauta")

      result =
        bauta_selector_live
        |> form("#bauta_form", %{bauta_form: %{session_name: session_name}})
        |> render_submit()

      assert result =~ "You selected your session name"

      result =
        bauta_selector_live
        |> form("#bauta_form", %{bauta_form: %{session_name: "invalid session name"}})
        |> render_submit()

      assert result =~ "must contain only alphanumeric characters and hyphens"

      result =
        bauta_selector_live
        |> form("#bauta_form", %{
          bauta_form: %{session_name: "non-existent-but-valid-session-name"}
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

      {:ok, bauta_selector_live, _html} =
        conn
        |> live(~p"/bauta")

      {:ok, _chat_live_view, html} =
        bauta_selector_live
        |> form("#bauta_form", %{bauta_form: %{session_name: session_name}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/chat/#{session_name}")

      assert html =~ "#{session_name}"
    end
  end
end
