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

      # Register a prekey bundle for the selected session so the chat can load
      Privee.PreKeyStore.register_bundle(selected_session.id, %{
        identity_key: "test_identity_key",
        registration_id: 12345,
        signed_prekey: %{key_id: 1, public_key: "test_spk", signature: "test_sig"},
        one_time_prekeys: [%{key_id: 1, public_key: "test_opk"}]
      })

      {:ok, _lv, html} =
        conn
        |> log_in_session(current_session)
        |> live(~p"/chat/#{selected_session.session_name}")

      assert html =~ selected_session.session_name
      assert html =~ "data-peer-prekey-bundle="
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

      assert html =~ "Create a new Privee"
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

      assert html =~ "Create a new Privee"
    end

    test "renders a chat message", %{conn: conn} do
      ciphertext = "encrypted_message_content_base64"
      header = ~s({"ratchetKey":"test_key","n":0,"pn":0})
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
            "ciphertext" => ciphertext,
            "header" => header
          }
        })

      expected_event = %{
        session_name: selected_session.session_name,
        check_focus: true
      }

      assert render(lv) =~ ciphertext

      assert_push_event(lv, "trigger_notification", ^expected_event)

      assert render(sender_lv) =~ ciphertext
    end
  end
end
