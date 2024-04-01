defmodule PriveeWeb.ChatHelpersTest do
  @moduledoc """
  Tests for the ChatHelpers module.
  """

  use PriveeWeb.ConnCase, async: true

  import Privee.SessionsFixtures
  import Privee.MessageFixtures
  import PriveeWeb.Chat.ChatHelpers

  describe "parse_messages/1" do
    test " correctly returns an emtpy list with an empty list in input" do
      assert [] == parse_messages([])
    end

    test " correctly returns no in_thread when a single message is passed" do
      message = message_fixture()
      assert [message] = parse_messages([message])
      refute message.in_thread
    end

    test " correctly returns the messages with indexes" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22] = parse_messages([message_11, message_12])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to

      assert message_21.index == 1
      refute message_22.index == 2
    end

    test " correctly returns no in_thread when two message from two different sessions are sent" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22] = parse_messages([message_11, message_12])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to

      refute message_21.in_thread
      refute message_22.in_thread
    end

    test " correctly returns no in_thread when three message from two different sessions are sent" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      message_13 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22, message_23] =
               parse_messages([message_11, message_12, message_13])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to
      assert message_13.text_from == message_23.text_from
      assert message_13.text_to == message_23.text_to

      refute message_21.in_thread
      refute message_22.in_thread
      refute message_23.in_thread
    end

    test " correctly returns ine in_thread when three message from two different sessions are sent" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      message_13 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22, message_23] =
               parse_messages([message_11, message_12, message_13])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to
      assert message_13.text_from == message_23.text_from
      assert message_13.text_to == message_23.text_to

      refute message_21.in_thread
      refute message_22.in_thread
      assert message_23.in_thread
    end
  end

  describe "add_message/2" do
    test " correctly returns no in_thread when a single message is passed" do
      message = message_fixture()
      assert [message] = add_message(message, [])
      refute message.in_thread
    end

    test " correctly returns no in_thread when two message from two different sessions are sent" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22] = add_message(message_12, [message_11])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to

      refute message_21.in_thread
      refute message_22.in_thread
    end

    test " correctly returns no in_thread when three message from two different sessions are sent" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      message_13 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22, message_23] =
               add_message(message_13, [message_11, message_12])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to
      assert message_13.text_from == message_23.text_from
      assert message_13.text_to == message_23.text_to

      refute message_21.in_thread
      refute message_22.in_thread
      refute message_23.in_thread
    end

    test " correctly returns ine in_thread when three message from two different sessions are sent" do
      session_1 = session_fixture()
      session_2 = session_fixture(%{session_name: Ecto.UUID.generate()})

      message_11 =
        message_fixture(%{
          from: session_1.id,
          to: session_2.id,
          text_from: "text 1",
          text_to: "text 1"
        })

      message_12 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      message_13 =
        message_fixture(%{
          from: session_2.id,
          to: session_1.id,
          text_from: "text 2",
          text_to: "text 2"
        })

      assert [message_21, message_22, message_23] =
               add_message(message_13, [message_11, message_12])

      assert message_11.text_from == message_21.text_from
      assert message_11.text_to == message_21.text_to
      assert message_12.text_from == message_22.text_from
      assert message_12.text_to == message_22.text_to
      assert message_13.text_from == message_23.text_from
      assert message_13.text_to == message_23.text_to

      refute message_21.in_thread
      refute message_22.in_thread
      assert message_23.in_thread
    end
  end
end
