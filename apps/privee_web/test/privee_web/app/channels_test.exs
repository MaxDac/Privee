defmodule PriveeWeb.App.ChannelsTest do
  use PriveeWeb.ChannelCase, async: true

  import Privee.PreKeyFixtures
  import Privee.SessionsFixtures

  alias Privee.PreKeyStore
  alias Privee.Sessions
  alias Privee.Sessions.Message
  alias PriveeWeb.App.AppAuth
  alias PriveeWeb.App.AppSocket
  alias PriveeWeb.App.ChatChannel
  alias PriveeWeb.App.SessionChannel
  alias PriveeWeb.Events

  defp setup_sessions(_context) do
    me = session_fixture()
    peer = session_fixture(%{session_name: generate_new_unique_session_name()})
    %{me: me, peer: peer, socket: app_socket(me)}
  end

  describe "connect" do
    test "authenticates with the app token" do
      session = session_fixture()
      token = session |> Sessions.generate_session_token() |> AppAuth.encode_token()

      assert {:ok, socket} = connect(AppSocket, %{}, connect_info: %{auth_token: token})
      assert socket.assigns.current_session.id == session.id
      assert "app_socket:" <> _ = AppSocket.id(socket)
    end

    test "rejects missing or invalid tokens" do
      assert :error = connect(AppSocket, %{})
      assert :error = connect(AppSocket, %{}, connect_info: %{auth_token: "nope"})

      unknown = AppAuth.encode_token(:crypto.strong_rand_bytes(32))
      assert :error = connect(AppSocket, %{}, connect_info: %{auth_token: unknown})
    end
  end

  describe "session channel" do
    setup :setup_sessions

    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, SessionChannel, "session")
      %{channel: channel}
    end

    test "publishes the identity and reports the status", %{channel: channel} do
      bundle = bundle_attrs()

      ref = push(channel, "publish_identity", bundle)
      assert_reply ref, :ok, %{ok: true}

      ref = push(channel, "signal_status", %{})
      assert_reply ref, :ok, %{identity_key: identity_key, max_age_ms: _}
      assert identity_key == bundle["identity_key"]
    end

    test "replies with an error for invalid key material", %{channel: channel} do
      ref = push(channel, "publish_identity", %{"identity_key" => "x"})
      assert_reply ref, :ok, %{error: _}
    end

    test "pushes identity_superseded when another device resets the identity", %{me: me} do
      :ok = PreKeyStore.publish_identity(me.id, bundle_attrs())
      other = app_socket(me)
      {:ok, _, other_channel} = subscribe_and_join(other, SessionChannel, "session")

      new_bundle = bundle_attrs()
      ref = push(other_channel, "reset_identity", new_bundle)
      assert_reply ref, :ok, %{ok: true}

      identity_key = new_bundle["identity_key"]
      assert_push "identity_superseded", %{identity_key: ^identity_key}
    end

    test "pushes replenish_prekeys when the pool runs low", %{me: me} do
      PriveeWeb.SignalKeys.maybe_notify_opk_low(me.id, 1)
      assert_push "replenish_prekeys", %{}
    end

    test "pushes content-free notifications for received messages", %{me: me, peer: peer} do
      Events.broadcast_new_message(%Message{
        id: 42,
        from: peer.id,
        to: me.id,
        sender_session_name: peer.session_name,
        body: "secret"
      })

      assert_push "message_received", payload
      assert payload == %{message_id: 42, from_session_name: peer.session_name}
    end

    test "rejects unknown events", %{channel: channel} do
      ref = push(channel, "nope", %{})
      assert_reply ref, :ok, %{error: "unknown_event"}
    end
  end

  describe "chat channel" do
    setup :setup_sessions

    setup %{me: me, peer: peer, socket: socket} do
      my_bundle = bundle_attrs()
      :ok = PreKeyStore.publish_identity(me.id, my_bundle)

      {:ok, reply, channel} =
        subscribe_and_join(socket, ChatChannel, "chat:#{peer.session_name}")

      assert reply == %{peer_session_name: peer.session_name}
      %{channel: channel, identity_key: my_bundle["identity_key"]}
    end

    defp open(channel) do
      ref = push(channel, "open_conversation", %{})
      assert_reply ref, :ok, %{epoch: epoch}
      epoch
    end

    defp send_params(epoch, identity_key) do
      %{
        "type" => 3,
        "body" => Base.encode64("ciphertext"),
        "client_nonce" => Ecto.UUID.generate(),
        "epoch" => epoch,
        "identity_key" => identity_key
      }
    end

    test "cannot be joined for unknown sessions or yourself", %{me: me, socket: socket} do
      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(
                 socket,
                 ChatChannel,
                 "chat:#{generate_new_unique_session_name()}"
               )

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, ChatChannel, "chat:#{me.session_name}")
    end

    test "sends, broadcasts and fetches messages", %{
      channel: channel,
      identity_key: identity_key
    } do
      epoch = open(channel)
      params = send_params(epoch, identity_key)
      nonce = params["client_nonce"]

      ref = push(channel, "send_message", params)
      assert_reply ref, :ok, %{id: id, seq: seq, epoch: ^epoch, client_nonce: ^nonce}

      assert_push "new_message", %{id: ^id, direction: "out", client_nonce: ^nonce}

      ref = push(channel, "fetch_messages", %{"epoch" => epoch, "after_seq" => 0})
      assert_reply ref, :ok, %{messages: [%{id: ^id, seq: ^seq}], next_cursor: _}
    end

    test "rejects sends from a superseded identity", %{channel: channel} do
      epoch = open(channel)
      ref = push(channel, "send_message", send_params(epoch, public_key()))
      assert_reply ref, :ok, %{error: "superseded"}
    end

    test "rejects malformed requests", %{channel: channel} do
      ref = push(channel, "send_message", %{})
      assert_reply ref, :ok, %{error: "invalid"}

      ref = push(channel, "fetch_messages", %{"epoch" => 1})
      assert_reply ref, :ok, %{error: "invalid"}
    end

    test "returns the peer bundle once published", %{channel: channel, peer: peer} do
      ref = push(channel, "request_peer_bundle", %{})
      assert_reply ref, :ok, %{error: "not_found"}

      :ok = PreKeyStore.publish_identity(peer.id, bundle_attrs())

      PriveeWeb.Endpoint.broadcast(
        PriveeWeb.SignalKeys.peer_topic(peer.id),
        "prekeys_available",
        %{}
      )

      assert_push "peer_keys_ready", %{}

      ref = push(channel, "request_peer_bundle", %{})
      assert_reply ref, :ok, %{bundle: %{}}
    end
  end
end
