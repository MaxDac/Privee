defmodule PriveeWeb.GuideLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  test "explains the app to visitors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/guide")

    for id <- ~w(#guide-purpose #guide-sessions #guide-start #guide-history #guide-commands) do
      assert has_element?(view, id)
    end

    assert has_element?(view, ~s|#guide-start-link[href="/"]|)
    assert has_element?(view, "#guide-link")
  end

  test "links signed-in sessions to the chat selection", %{conn: conn} do
    conn = log_in_session(conn, session_fixture())
    {:ok, view, _html} = live(conn, ~p"/guide")

    assert has_element?(view, ~s|#guide-start-link[href="/privee"]|)
  end
end
