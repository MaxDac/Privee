defmodule PriveeWeb.NotificationsLiveTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  alias Privee.Sessions.Message

  setup %{conn: conn} do
    me = session_fixture()
    peer = session_fixture(%{session_name: generate_new_unique_session_name()})
    other = session_fixture(%{session_name: generate_new_unique_session_name()})
    %{conn: log_in_session(conn, me), me: me, peer: peer, other: other}
  end

  defp broadcast(from, to) do
    message = %Message{
      id: Ecto.UUID.generate(),
      from: from.id,
      to: to.id,
      sender_session_name: from.session_name,
      body: "ciphertext"
    }

    PriveeWeb.Endpoint.broadcast("receiver:#{to.id}", "message_received", message)
    message
  end

  test "the selector page notifies without message content", %{conn: conn, me: me, peer: peer} do
    {:ok, lv, _html} = live(conn, ~p"/privee")
    %{id: id} = broadcast(peer, me)
    assert_push_event(lv, "trigger_notification", payload)

    assert payload == %{
             message_id: id,
             to: me.id,
             session_name: peer.session_name,
             check_focus: false
           }
  end

  test "the chat page checks focus only for the open conversation", %{
    conn: conn,
    me: me,
    peer: peer,
    other: other
  } do
    {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")

    broadcast(peer, me)
    assert_push_event(lv, "trigger_notification", %{check_focus: true})

    broadcast(other, me)
    assert_push_event(lv, "trigger_notification", %{check_focus: false})
  end
end
