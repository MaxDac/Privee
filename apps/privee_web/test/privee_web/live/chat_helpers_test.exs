defmodule PriveeWeb.ChatHelpersTest do
  @moduledoc """
  Tests for the ChatHelpers module.
  """

  use ExUnit.Case, async: true

  alias Privee.Sessions.Message

  import PriveeWeb.Chat.ChatHelpers

  defp msg(from, to, id \\ Ecto.UUID.generate()) do
    %Message{id: id, from: from, to: to, type: 2, body: "YQ==", client_nonce: "n-#{id}"}
  end

  describe "parse_messages/1" do
    test "returns an empty list for an empty list" do
      assert {nil, []} == parse_messages([])
    end

    test "preserves server ids and order" do
      m1 = msg(1, 2)
      m2 = msg(2, 1)
      assert {last, [p1, p2]} = parse_messages([m1, m2])
      assert p1.id == m1.id and p2.id == m2.id
      assert last == p2
    end

    test "a single message is not in a thread" do
      assert {_, [m]} = parse_messages([msg(1, 2)])
      refute m.in_thread
    end

    test "alternating senders are not in a thread" do
      {_, parsed} = parse_messages([msg(1, 2), msg(2, 1), msg(1, 2)])
      refute Enum.any?(parsed, & &1.in_thread)
    end

    test "consecutive messages from the same sender are in a thread" do
      {_, [a, b, c]} = parse_messages([msg(1, 2), msg(2, 1), msg(2, 1)])
      refute a.in_thread
      refute b.in_thread
      assert c.in_thread
    end
  end

  describe "add_message/2" do
    test "first message is not in a thread" do
      refute add_message(msg(1, 2), nil).in_thread
    end

    test "different sender is not in a thread" do
      refute add_message(msg(2, 1), msg(1, 2)).in_thread
    end

    test "same sender is in a thread and keeps its id" do
      m = msg(2, 1)
      added = add_message(m, msg(2, 1))
      assert added.in_thread
      assert added.id == m.id
    end
  end

  describe "serialize_message/2" do
    test "discloses the nonce only to the sender" do
      m = msg(1, 2)
      assert %{direction: "out", client_nonce: nonce} = serialize_message(m, 1)
      assert nonce == m.client_nonce
      assert %{direction: "in", client_nonce: nil} = serialize_message(m, 2)
    end
  end
end
