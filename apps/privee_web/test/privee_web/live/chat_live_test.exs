defmodule PriveeWeb.ChatLiveTest do
  @moduledoc """
  Chat LiveView test.
  """

  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.PreKeyFixtures
  import Privee.SessionsFixtures

  alias Privee.Chats
  alias Privee.PreKeyStore
  alias Privee.Sessions.Message

  defp setup_chat(%{conn: conn}) do
    me = session_fixture()
    peer = session_fixture(%{session_name: generate_new_unique_session_name()})
    my_bundle = bundle_attrs()
    :ok = PreKeyStore.publish_identity(me.id, my_bundle)

    %{
      conn: log_in_session(conn, me),
      me: me,
      peer: peer,
      identity_key: my_bundle["identity_key"]
    }
  end

  defp send_params(epoch, identity_key, overrides \\ %{}) do
    Map.merge(
      %{
        "type" => 3,
        "body" => Base.encode64("ciphertext"),
        "client_nonce" => Ecto.UUID.generate(),
        "epoch" => epoch,
        "identity_key" => identity_key
      },
      overrides
    )
  end

  defp open_conversation(lv) do
    render_hook(lv, "open_conversation", %{})
    assert_reply(lv, %{epoch: epoch})
    epoch
  end

  describe "navigation" do
    setup :setup_chat

    test "renders the chat view", %{conn: conn, peer: peer} do
      {:ok, lv, html} = live(conn, ~p"/chat/#{peer.session_name}")
      assert html =~ peer.session_name
      assert has_element?(lv, "#chat-screen[phx-hook=ChatScreen]")
      assert has_element?(lv, "#chat-local-history[phx-update=ignore]")
    end

    test "redirects to the privee page when the logo is clicked", %{conn: conn, peer: peer} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")

      {:ok, _, html} =
        lv
        |> element("#logo-button")
        |> render_click()
        |> follow_redirect(conn, ~p"/privee")

      assert html =~ "Create a new Privee"
    end

    test "redirects to the privee selector view when the session does not exist", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> live(~p"/chat/#{generate_new_unique_session_name()}")
        |> follow_redirect(conn, ~p"/privee")

      assert html =~ "Create a new Privee"
    end

    test "redirects when chatting with yourself", %{conn: conn, me: me} do
      assert {:error, {:live_redirect, %{to: "/privee"}}} =
               live(conn, ~p"/chat/#{me.session_name}")
    end
  end

  test "redirects to the register view when the user is not logged in", %{conn: conn} do
    selected_session = session_fixture()

    assert {:ok, _conn} =
             conn
             |> live(~p"/chat/#{selected_session.session_name}")
             |> follow_redirect(conn, ~p"/")
  end

  describe "plaintext never reaches the server" do
    setup :setup_chat

    test "the composer input has no name and is not in a LiveView form", %{
      conn: conn,
      peer: peer
    } do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      assert has_element?(lv, "#chat-text")
      refute has_element?(lv, "#chat-text[name]")
      refute has_element?(lv, "form[phx-change]")
      refute has_element?(lv, "form[phx-submit] #chat-text")
    end

    test "legacy form events do not crash and ask to reload", %{conn: conn, peer: peer} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      html = render_hook(lv, "create", %{"message" => %{"text" => "hello"}})
      assert html =~ "Please reload"
      assert Process.alive?(lv.pid)
    end
  end

  describe "keys" do
    setup :setup_chat

    test "mounting does not consume one-time prekeys", %{conn: conn, peer: peer} do
      :ok = PreKeyStore.publish_identity(peer.id, bundle_attrs(opk_ids: 1..5))
      {:ok, _lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      assert PreKeyStore.count_one_time_prekeys(peer.id) == 5
    end

    test "request_peer_bundle pops one prekey, rate limited", %{conn: conn, peer: peer} do
      :ok = PreKeyStore.publish_identity(peer.id, bundle_attrs(opk_ids: 1..10))
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")

      for id <- 1..3 do
        render_hook(lv, "request_peer_bundle", %{})
        assert_reply(lv, %{bundle: %{one_time_prekey: %{key_id: ^id}}})
      end

      render_hook(lv, "request_peer_bundle", %{})
      assert_reply(lv, %{bundle: %{one_time_prekey: nil, signed_prekey: %{key_id: 1}}})
      assert PreKeyStore.count_one_time_prekeys(peer.id) == 7
    end

    test "request_peer_bundle without a peer bundle", %{conn: conn, peer: peer} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      render_hook(lv, "request_peer_bundle", %{})
      assert_reply(lv, %{error: "not_found"})
    end

    test "peer publishing keys pushes a content-free peer_keys_ready", %{
      conn: conn,
      peer: peer
    } do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      PriveeWeb.Endpoint.broadcast("prekeys:#{peer.id}", "prekeys_available", %{})
      assert_push_event(lv, "peer_keys_ready", payload)
      assert payload == %{}
    end

    test "signal_status reports the published identity", %{
      conn: conn,
      peer: peer,
      identity_key: ik
    } do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      render_hook(lv, "signal_status", %{})
      assert_reply(lv, %{identity_key: ^ik, opk_count: 3, max_opk_id: 3, max_age_ms: _})
    end

    test "add_prekeys requires the current identity", %{conn: conn, peer: peer, identity_key: ik} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      opks = one_time_prekeys(4..5)

      render_hook(lv, "add_prekeys", %{"identity_key" => public_key(), "one_time_prekeys" => opks})

      assert_reply(lv, %{error: "identity_mismatch"})

      render_hook(lv, "add_prekeys", %{"identity_key" => ik, "one_time_prekeys" => opks})
      assert_reply(lv, %{ok: true})
    end

    test "an opk_low notification asks the owner to replenish", %{
      conn: conn,
      me: me,
      peer: peer
    } do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      PriveeWeb.SignalKeysLive.maybe_notify_opk_low(me.id, 2)
      assert_push_event(lv, "replenish_prekeys", %{})
    end

    test "reset_identity supersedes other devices", %{conn: conn, me: me, peer: peer} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      {:ok, other, _html} = live(conn, ~p"/privee")
      new = bundle_attrs()
      new_ik = new["identity_key"]

      render_hook(lv, "reset_identity", new)
      assert_reply(lv, %{ok: true})
      assert_push_event(other, "identity_superseded", %{identity_key: ^new_ik})
      assert PreKeyStore.identity_key(me.id) == new_ik
    end
  end

  describe "send_message" do
    setup :setup_chat

    test "stores, broadcasts and replies with server fields", %{
      conn: conn,
      me: me,
      peer: peer,
      identity_key: ik
    } do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)
      params = send_params(epoch, ik)
      nonce = params["client_nonce"]

      render_hook(lv, "send_message", params)
      assert_reply(lv, %{id: id, seq: seq, epoch: ^epoch, client_nonce: ^nonce})
      assert is_integer(seq)

      assert has_element?(lv, "#msg-#{id} [data-signal-message][data-client-nonce='#{nonce}']")

      assert {^epoch, [%Message{id: ^id, from: from, to: to, sender_session_name: name}]} =
               Chats.latest_messages(me.id, peer.id)

      assert from == me.id and to == peer.id and name == me.session_name
    end

    test "ignores spoofed server fields", %{conn: conn, me: me, peer: peer, identity_key: ik} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)
      intruder = session_fixture(%{session_name: generate_new_unique_session_name()})

      params =
        send_params(epoch, ik, %{
          "from" => intruder.id,
          "to" => intruder.id,
          "sender_session_name" => "spoofed",
          "text" => "plaintext"
        })

      render_hook(lv, "send_message", params)
      assert_reply(lv, %{id: _})

      assert {_, [%Message{from: from, to: to, sender_session_name: name} = m]} =
               Chats.latest_messages(me.id, peer.id)

      assert {from, to, name} == {me.id, peer.id, me.session_name}
      refute Map.has_key?(Map.from_struct(m), :text)
    end

    test "a duplicate nonce is not broadcast twice", %{
      conn: conn,
      me: me,
      peer: peer,
      identity_key: ik
    } do
      PriveeWeb.Endpoint.subscribe("receiver:#{peer.id}")
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)
      params = send_params(epoch, ik)

      render_hook(lv, "send_message", params)
      assert_reply(lv, %{id: id})
      render_hook(lv, "send_message", params)
      assert_reply(lv, %{id: ^id})

      assert_receive %{event: "message_received"}
      refute_receive %{event: "message_received"}, 50
      assert {_, [_]} = Chats.latest_messages(me.id, peer.id)
    end

    test "rejects a stale epoch", %{conn: conn, peer: peer, identity_key: ik} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)
      render_hook(lv, "send_message", send_params("stale", ik))
      assert_reply(lv, %{error: "stale_epoch", epoch: ^epoch})
    end

    test "rejects a superseded identity", %{conn: conn, peer: peer} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)
      render_hook(lv, "send_message", send_params(epoch, public_key()))
      assert_reply(lv, %{error: "superseded"})
    end

    test "accepts an identity published by another tab after mount", %{
      conn: conn,
      me: me,
      peer: peer
    } do
      :ok = PreKeyStore.remove_bundle(me.id)
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)

      new_bundle = bundle_attrs()
      :ok = PreKeyStore.publish_identity(me.id, new_bundle)

      render_hook(lv, "send_message", send_params(epoch, new_bundle["identity_key"]))
      assert_reply(lv, %{id: _, epoch: ^epoch})
    end

    test "rejects invalid payloads", %{conn: conn, peer: peer, identity_key: ik} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)

      for overrides <- [%{"type" => 2}, %{"body" => "not base64!"}, %{"client_nonce" => "x"}] do
        render_hook(lv, "send_message", send_params(epoch, ik, overrides))
        assert_reply(lv, %{error: "invalid"})
      end

      render_hook(lv, "send_message", %{"body" => "x"})
      assert_reply(lv, %{error: "invalid"})
    end
  end

  describe "history" do
    setup :setup_chat

    test "mount renders the latest messages ascending with server ids", %{
      conn: conn,
      me: me,
      peer: peer
    } do
      {:ok, epoch} = Chats.open_conversation(me.id, peer.id)

      ids =
        for from <- [me.id, peer.id, peer.id] do
          to = if from == me.id, do: peer.id, else: me.id

          {:ok, m} =
            Chats.create_message(
              %Message{
                from: from,
                to: to,
                sender_session_name: "x",
                type: 1,
                body: Base.encode64("c"),
                client_nonce: Ecto.UUID.generate()
              },
              epoch
            )

          m.id
        end

      {:ok, lv, html} = live(conn, ~p"/chat/#{peer.session_name}")

      for id <- ids, do: assert(has_element?(lv, "#msg-#{id}"))
      positions = Enum.map(ids, fn id -> :binary.match(html, "msg-#{id}") |> elem(0) end)
      assert positions == Enum.sort(positions)

      [own | _] = ids
      assert has_element?(lv, "#msg-#{own} [data-direction=out]")
      refute has_element?(lv, "#msg-#{List.last(ids)} [data-client-nonce]")
    end

    test "fetch_messages pages forward", %{conn: conn, peer: peer, identity_key: ik} do
      {:ok, lv, _html} = live(conn, ~p"/chat/#{peer.session_name}")
      epoch = open_conversation(lv)

      for _ <- 1..3 do
        render_hook(lv, "send_message", send_params(epoch, ik))
        assert_reply(lv, %{id: _})
      end

      render_hook(lv, "fetch_messages", %{"epoch" => epoch, "after_seq" => 0})
      assert_reply(lv, %{messages: [first | _] = messages, next_cursor: nil})
      assert length(messages) == 3
      assert first.direction == "out"

      render_hook(lv, "fetch_messages", %{"epoch" => epoch, "after_seq" => first.seq})
      assert_reply(lv, %{messages: rest})
      assert length(rest) == 2
    end
  end
end
