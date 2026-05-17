defmodule Privee.ChatsTest do
  @moduledoc """
  Unit tests for the Privee ETS implementation for the chat messages.
  """

  use Privee.DataCase

  alias Privee.Chats
  alias Privee.Sessions.Message

  import Privee.SessionsFixtures

  describe "ETS lookup" do
    setup do
      Chats.start_link()
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      %{session_1: session_1, session_2: session_2}
    end

    test " doesn't throw if already created" do
      assert is_nil(Chats.create_database())
    end

    test " correctly creates the table, allowing simple operations", %{
      session_1: session_1,
      session_2: session_2
    } do
      message_1 = %Message{
        from: session_1.id,
        to: session_2.id,
        ciphertext: "encrypted_msg_1",
        header: ~s({"ratchetKey":"key1","n":0,"pn":0})
      }

      message_2 = %Message{
        from: session_2.id,
        to: session_1.id,
        ciphertext: "encrypted_msg_2",
        header: ~s({"ratchetKey":"key2","n":0,"pn":0})
      }

      Chats.create_message(message_1)
      Chats.create_message(message_2)

      chat_screen_for_session_1 = Chats.get_messages(session_1.id, session_2.id)

      assert 2 == Enum.count(chat_screen_for_session_1)
      assert Enum.any?(chat_screen_for_session_1, &(&1.ciphertext == message_1.ciphertext))
      assert Enum.any?(chat_screen_for_session_1, &(&1.ciphertext == message_2.ciphertext))
    end

    test " allows insertion of two message with the same text, and returns them",
         %{session_1: session_1, session_2: session_2} do
      message_1 = %Message{
        from: session_1.id,
        to: session_2.id,
        ciphertext: "encrypted_msg_same",
        header: ~s({"ratchetKey":"key1","n":0,"pn":0})
      }

      message_2 = %Message{
        from: session_1.id,
        to: session_2.id,
        ciphertext: "encrypted_msg_same",
        header: ~s({"ratchetKey":"key1","n":1,"pn":0})
      }

      Chats.create_message(message_1)
      Chats.create_message(message_2)

      chat_screen_for_session_1 = Chats.get_messages(session_1.id, session_2.id)

      assert 2 == Enum.count(chat_screen_for_session_1)
      assert Enum.any?(chat_screen_for_session_1, &(&1.ciphertext == message_1.ciphertext))
      assert Enum.any?(chat_screen_for_session_1, &(&1.header == message_2.header))
    end
  end
end
