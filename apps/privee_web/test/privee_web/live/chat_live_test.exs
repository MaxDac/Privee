defmodule PriveeWeb.ChatLiveTest do
  @moduledoc """
  Chat LiveView test.
  """

  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  describe "chat_live" do
    test "renders the chat view when the user is logged in", %{conn: conn} do
      current_session = session_fixture()
      selected_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      {:ok, _lv, html} =
        conn
        |> log_in_session(current_session)
        |> live(~p"/chat/#{selected_session.session_name}")

      assert html =~ selected_session.session_name
    end

    test "redirects to the register view when the user is not logged in", %{conn: conn} do
      selected_session = session_fixture()

      result =
        conn
        |> live(~p"/chat/#{selected_session.session_name}")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "redirects to the privee selector view when the session does not exist", %{conn: conn} do
      current_session = session_fixture()
      selected_session_name = generate_new_unique_session_name()

      # Rebinding the logged on connection
      conn =
        conn
        |> log_in_session(current_session)

      {:ok, _lv, html} =
        conn
        |> live(~p"/chat/#{selected_session_name}")
        |> follow_redirect(conn, ~p"/privee")

      assert html =~ "Create a new Privée"
    end

    test "renders a chat message", %{conn: conn} do
      message_text = "some message"
      current_session = session_fixture()
      selected_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      {:ok, lv, _html} =
        conn
        |> log_in_session(current_session)
        |> live(~p"/chat/#{selected_session.session_name}")

      {:ok, sender_lv, _html} =
        conn
        |> log_in_session(selected_session)
        |> live(~p"/chat/#{current_session.session_name}")

      _ =
        sender_lv
        |> form("#chat_form", %{
          message: %{
            from: selected_session.id,
            to: current_session.id,
            sender_session_name: selected_session.session_name,
            text: message_text
          }
        })
        |> render_submit()

      expected_event = %{
        session_name: selected_session.session_name,
        text: message_text,
        check_focus: true
      }

      assert render(lv) =~ message_text
      assert_push_event(lv, "trigger_notification", ^expected_event)
      assert render(sender_lv) =~ message_text
    end
  end
end
