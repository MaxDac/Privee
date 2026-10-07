defmodule Privee.ChatsTest do
  @moduledoc """
  Unit tests for the ETS-backed ephemeral chat storage.
  """

  # Tables are global: tests must not run concurrently.
  use ExUnit.Case, async: false

  alias Privee.Chats
  alias Privee.Sessions.Message

  @a 1_000_001
  @b 1_000_002

  setup do
    for t <- [:chat_messages, :chat_conversations, :chat_nonces], do: :ets.delete_all_objects(t)
    prev = Application.get_env(:privee, Chats)
    on_exit(fn -> restore_env(prev) end)
    :ok
  end

  defp restore_env(nil), do: Application.delete_env(:privee, Chats)
  defp restore_env(prev), do: Application.put_env(:privee, Chats, prev)

  defp put_config(opts), do: Application.put_env(:privee, Chats, opts)

  defp msg(from \\ @a, to \\ @b, nonce \\ Ecto.UUID.generate()) do
    %Message{
      from: from,
      to: to,
      sender_session_name: "s#{from}",
      type: 2,
      body: Base.encode64("ct"),
      client_nonce: nonce
    }
  end

  defp open!(a \\ @a, b \\ @b) do
    {:ok, epoch} = Chats.open_conversation(a, b)
    epoch
  end

  describe "open_conversation/2" do
    test "is symmetric and stable" do
      epoch = open!()
      assert {:ok, ^epoch} = Chats.open_conversation(@b, @a)
      assert Chats.current_epoch(@a, @b) == epoch
    end

    test "rotates after inactivity ttl" do
      put_config(ttl_ms: 1000)
      now = System.system_time(:millisecond)
      {:ok, e1} = Chats.open_conversation(@a, @b, now)
      {:ok, e2} = Chats.open_conversation(@a, @b, now + 2000)
      assert e1 != e2
    end

    test "rotates after max_age even when active" do
      put_config(ttl_ms: 10_000, max_age_ms: 5000)
      now = System.system_time(:millisecond)
      {:ok, e1} = Chats.open_conversation(@a, @b, now)

      for t <- [1000, 2000, 3000, 4000] do
        assert {:ok, _} = Chats.create_message(msg(), e1, now + t)
      end

      {:ok, e2} = Chats.open_conversation(@a, @b, now + 6000)
      assert e1 != e2
    end
  end

  describe "create_message/2" do
    test "stores and returns server-assigned fields" do
      epoch = open!()
      assert {:ok, %Message{id: id, seq: seq, epoch: ^epoch}} = Chats.create_message(msg(), epoch)
      assert is_binary(id) and is_integer(seq)
      assert {^epoch, [%Message{id: ^id}]} = Chats.latest_messages(@b, @a)
    end

    test "rejects a stale epoch" do
      open!()
      assert {:error, {:stale_epoch, current}} = Chats.create_message(msg(), "old")
      assert current == Chats.current_epoch(@a, @b)
    end

    test "rotates at the message cap before inserting" do
      put_config(max_messages: 2)
      epoch = open!()
      assert {:ok, _} = Chats.create_message(msg(), epoch)
      assert {:ok, _} = Chats.create_message(msg(), epoch)
      assert {:error, {:stale_epoch, new_epoch}} = Chats.create_message(msg(), epoch)
      assert new_epoch != epoch
      assert {:ok, _} = Chats.create_message(msg(), new_epoch)
      assert {^new_epoch, [_]} = Chats.latest_messages(@a, @b)
    end

    test "send after ttl expiry (before sweep) is rejected as stale" do
      put_config(ttl_ms: 1000)
      now = System.system_time(:millisecond)
      {:ok, epoch} = Chats.open_conversation(@a, @b, now)
      assert {:error, {:stale_epoch, _}} = Chats.create_message(msg(), epoch, now + 5000)
    end

    test "deduplicates by nonce" do
      epoch = open!()
      nonce = Ecto.UUID.generate()
      assert {:ok, m} = Chats.create_message(msg(@a, @b, nonce), epoch)
      assert {:duplicate, ^m} = Chats.create_message(msg(@a, @b, nonce), epoch)
      assert {_, [_]} = Chats.latest_messages(@a, @b)
    end

    test "nonces are scoped per sender" do
      epoch = open!()
      nonce = Ecto.UUID.generate()
      assert {:ok, _} = Chats.create_message(msg(@a, @b, nonce), epoch)
      assert {:ok, _} = Chats.create_message(msg(@b, @a, nonce), epoch)
    end

    test "concurrent sends with one nonce insert exactly once" do
      epoch = open!()
      nonce = Ecto.UUID.generate()

      results =
        1..50
        |> Task.async_stream(fn _ -> Chats.create_message(msg(@a, @b, nonce), epoch) end,
          max_concurrency: 50,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.all?(results, &match?({tag, _} when tag in [:ok, :duplicate, :error], &1))
      assert {_, [_]} = Chats.latest_messages(@a, @b)
    end

    test "a pending claim held by a live process is in flight" do
      epoch = open!()
      nonce = Ecto.UUID.generate()
      parent = self()

      holder =
        spawn(fn ->
          :ets.insert(
            :chat_nonces,
            {{@a, nonce}, :pending, Chats.conv_key(@a, @b), epoch, Ecto.UUID.generate(), 1,
             self(), 0}
          )

          send(parent, :claimed)
          Process.sleep(:infinity)
        end)

      assert_receive :claimed
      assert {:error, :in_flight} = Chats.create_message(msg(@a, @b, nonce), epoch)
      Process.exit(holder, :kill)
    end

    test "an abandoned claim without a message is reclaimed" do
      epoch = open!()
      nonce = Ecto.UUID.generate()
      dead = dead_pid()

      :ets.insert(
        :chat_nonces,
        {{@a, nonce}, :pending, Chats.conv_key(@a, @b), epoch, Ecto.UUID.generate(), 1, dead, 0}
      )

      assert {:ok, _} = Chats.create_message(msg(@a, @b, nonce), epoch)
      assert {_, [_]} = Chats.latest_messages(@a, @b)
    end

    test "an abandoned claim whose message was inserted is reconciled, not duplicated" do
      epoch = open!()
      nonce = Ecto.UUID.generate()
      key = Chats.conv_key(@a, @b)
      seq = System.unique_integer([:monotonic, :positive])
      id = Ecto.UUID.generate()
      stored = %{msg(@a, @b, nonce) | id: id, seq: seq, epoch: epoch}
      :ets.insert(:chat_messages, {{key, epoch, seq}, 0, stored})
      :ets.insert(:chat_nonces, {{@a, nonce}, :pending, key, epoch, id, seq, dead_pid(), 0})

      assert {:duplicate, %Message{id: ^id}} = Chats.create_message(msg(@a, @b, nonce), epoch)
      assert {_, [_]} = Chats.latest_messages(@a, @b)
    end

    test "a committed claim with a missing row triggers a fresh insert" do
      epoch = open!()
      nonce = Ecto.UUID.generate()
      {:ok, m} = Chats.create_message(msg(@a, @b, nonce), epoch)
      :ets.delete(:chat_messages, {Chats.conv_key(@a, @b), epoch, m.seq})

      assert {:ok, m2} = Chats.create_message(msg(@a, @b, nonce), epoch)
      assert m2.id != m.id
    end
  end

  describe "reads" do
    test "latest_messages returns the newest page ascending" do
      epoch = open!()
      ids = for _ <- 1..5, do: elem(Chats.create_message(msg(), epoch), 1).id

      assert {^epoch, page} = Chats.latest_messages(@a, @b, 3)
      assert Enum.map(page, & &1.id) == Enum.drop(ids, 2)
    end

    test "latest_messages ignores other conversations" do
      epoch = open!()
      other = open!(@a, 42)
      {:ok, _} = Chats.create_message(msg(@a, 42), other)
      {:ok, m} = Chats.create_message(msg(), epoch)
      assert {_, [%Message{id: id}]} = Chats.latest_messages(@a, @b)
      assert id == m.id
    end

    test "messages_after pages forward" do
      epoch = open!()
      ids = for _ <- 1..5, do: elem(Chats.create_message(msg(), epoch), 1).id

      {p1, c1} = Chats.messages_after(@a, @b, epoch, 0, 2)
      {p2, c2} = Chats.messages_after(@a, @b, epoch, c1, 2)
      {p3, c3} = Chats.messages_after(@a, @b, epoch, c2, 2)

      assert Enum.map(p1 ++ p2 ++ p3, & &1.id) == ids
      assert is_nil(c3)
    end

    test "unknown conversation reads are empty" do
      assert {nil, []} = Chats.latest_messages(1, 2)
      assert {[], nil} = Chats.messages_after(1, 2, "x", 0)
    end
  end

  describe "end_conversations/1" do
    test "ends every conversation of the session and drops its messages" do
      c = 1_000_003
      e_ab = open!(@a, @b)
      e_bc = open!(@b, c)
      e_ac = open!(@a, c)
      {:ok, _} = Chats.create_message(msg(@a, @b), e_ab)
      {:ok, _} = Chats.create_message(msg(c, @b), e_bc)
      {:ok, _} = Chats.create_message(msg(@a, c), e_ac)

      assert :ok = Chats.end_conversations(@b)

      assert Chats.current_epoch(@a, @b) == nil
      assert Chats.current_epoch(@b, c) == nil
      assert Chats.current_epoch(@a, c) == e_ac
      assert {:error, {:stale_epoch, _}} = Chats.create_message(msg(@a, @b), e_ab)
      assert {_, []} = Chats.latest_messages(@a, @b)
      assert {^e_ac, [_]} = Chats.latest_messages(@a, c)
    end
  end

  describe "sweep/1" do
    test "drops expired conversations with their messages and nonces" do
      put_config(ttl_ms: 1000)
      now = System.system_time(:millisecond)
      {:ok, epoch} = Chats.open_conversation(@a, @b, now)
      {:ok, _} = Chats.create_message(msg(), epoch, now)

      Chats.sweep(now + 5000)

      assert Chats.current_epoch(@a, @b) == nil
      assert :ets.info(:chat_messages, :size) == 0
      assert :ets.info(:chat_nonces, :size) == 0
    end

    test "keeps live conversations" do
      epoch = open!()
      {:ok, _} = Chats.create_message(msg(), epoch)
      Chats.sweep()
      assert {^epoch, [_]} = Chats.latest_messages(@a, @b)
    end

    test "drops pending claims of dead owners" do
      epoch = open!()
      key = Chats.conv_key(@a, @b)
      :ets.insert(:chat_nonces, {{@a, "n"}, :pending, key, epoch, "id", 1, dead_pid(), 0})
      Chats.sweep()
      assert :ets.lookup(:chat_nonces, {@a, "n"}) == []
    end

    test "an insert racing an epoch rotation does not survive in the old epoch" do
      put_config(ttl_ms: 1000)
      now = System.system_time(:millisecond)
      {:ok, epoch} = Chats.open_conversation(@a, @b, now)
      {:ok, e2} = Chats.open_conversation(@a, @b, now + 5000)
      assert {:error, {:stale_epoch, ^e2}} = Chats.create_message(msg(), epoch, now + 5000)
      assert {^e2, []} = Chats.latest_messages(@a, @b)
    end
  end

  defp dead_pid do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}
    pid
  end
end
