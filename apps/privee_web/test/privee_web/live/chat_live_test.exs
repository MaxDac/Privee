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

      {:ok, lv, html} =
        conn
        |> log_in_session(current_session)
        |> live(~p"/chat/#{selected_session.session_name}")

      expected_event_payload = %{
        current: current_session.public_key,
        selected: selected_session.public_key
      }

      assert_push_event(lv, "sending_keys", ^expected_event_payload)
      assert html =~ selected_session.session_name
    end

    test "redirects to the privee page when the logo is clicked", %{conn: conn} do
      current_session = session_fixture()
      selected_session = session_fixture(%{session_name: generate_new_unique_session_name()})

      # Rebinding the logged on connection
      conn = log_in_session(conn, current_session)

      {:ok, lv, _html} = live(conn, ~p"/chat/#{selected_session.session_name}")

      {:ok, _, html} =
        lv
        |> element("#logo-button")
        |> render_click()
        |> follow_redirect(conn, ~p"/privee")

      assert html =~ "Create a new Privée"
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
      message_text_from = "some message from"
      message_text_to = "some message to"
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
        |> form("#chat-form", %{
          message: %{
            from: selected_session.id,
            to: current_session.id,
            sender_session_name: selected_session.session_name
          }
        })
        |> render_submit(%{
          "message" => %{
            "text_from" => message_text_from,
            "text_to" => message_text_to
          }
        })

      expected_event = %{
        session_name: selected_session.session_name,
        text: message_text_to,
        check_focus: true
      }

      assert render(lv) =~ message_text_to

      assert_push_event(lv, "trigger_notification", ^expected_event)

      assert render(sender_lv) =~ message_text_from
    end
  end
end
