defmodule PriveeWeb.ChatActions do
  @moduledoc """
  Transport-independent handling of the chat events between the current
  session (`me`) and a peer, shared by `PriveeWeb.Chat.ChatLive` and the app
  channel (`PriveeWeb.App.ChatChannel`). The server never sees plaintext.

    * `open_conversation` - `%{epoch}`: the conversation epoch sessions bind to.
    * `request_peer_bundle` - `%{peer_id, bundle}`: the peer's public prekey
      bundle. At most 3 one-time prekeys per requester/peer pair are popped every
      10 minutes.
    * `send_message` - `%{type, body, client_nonce, epoch, identity_key}` ->
      `%{id, seq, epoch, client_nonce}` or `%{error}`.
    * `fetch_messages` - `%{epoch, after_seq}` -> `%{messages, next_cursor}`.
  """

  alias Privee.Chats
  alias Privee.PreKeyStore
  alias Privee.RateLimiter
  alias Privee.Sessions
  alias Privee.Sessions.Message
  alias PriveeWeb.Events
  alias PriveeWeb.SignalKeys

  import PriveeWeb.Chat.ChatHelpers, only: [serialize_message: 2]

  @opk_pops_per_window 3
  @opk_window_ms :timer.minutes(10)
  @max_page_size 200

  @doc """
  Resolves the peer a chat with `me` can be opened with, by session name.
  """
  @spec find_peer(Sessions.Session.t(), term()) :: {:ok, Sessions.Session.t()} | :error
  def find_peer(me, peer_session_name) when is_binary(peer_session_name) do
    case Sessions.get_session_by_session_name(peer_session_name) do
      %{id: id} = peer when id != me.id -> {:ok, peer}
      _ -> :error
    end
  end

  def find_peer(_me, _peer_session_name), do: :error

  @doc "Opens (or rejoins) the conversation between `me` and `peer`."
  def open_conversation(me, peer) do
    case Chats.open_conversation(me.id, peer.id) do
      {:ok, epoch} -> %{epoch: epoch}
      {:error, reason} -> %{error: to_string(reason)}
    end
  end

  @doc "Returns the public prekey bundle of `peer`, popping a one-time prekey if allowed."
  def request_peer_bundle(me, peer) do
    pop? =
      RateLimiter.hit({:opk_pop, me.id, peer.id}, @opk_pops_per_window, @opk_window_ms) == :ok

    case PreKeyStore.fetch_bundle(peer.id, pop_one_time_prekey: pop?) do
      {:ok, bundle, remaining} ->
        if pop?, do: SignalKeys.maybe_notify_opk_low(peer.id, remaining)
        %{peer_id: peer.id, bundle: bundle}

      {:error, :not_found} ->
        %{peer_id: peer.id, error: "not_found"}
    end
  end

  @doc """
  Stores an encrypted message from `me` to `peer` and broadcasts it.

  `known_identity_key` is the identity key the caller believes is published for
  `me`. It is refreshed from the store when it differs from the claimed one.
  Returns `{reply, identity_key}`, with the possibly refreshed identity key.
  """
  def send_message(me, peer, %{"epoch" => epoch} = params, known_identity_key)
      when is_binary(epoch) do
    identity_key = refresh_identity_key(me, known_identity_key, params["identity_key"])

    changeset =
      Sessions.change_message(
        %Message{from: me.id, to: peer.id, sender_session_name: me.session_name},
        params
      )

    reply =
      cond do
        is_nil(identity_key) or params["identity_key"] != identity_key ->
          %{error: "superseded"}

        not changeset.valid? ->
          %{error: "invalid"}

        true ->
          changeset
          |> Ecto.Changeset.apply_changes()
          |> Chats.create_message(epoch)
          |> send_reply()
      end

    {reply, identity_key}
  end

  def send_message(_me, _peer, _params, known_identity_key),
    do: {%{error: "invalid"}, known_identity_key}

  @doc "Returns a page of the messages exchanged after `after_seq` in `epoch`."
  def fetch_messages(me, peer, %{"epoch" => epoch, "after_seq" => after_seq})
      when is_binary(epoch) and is_integer(after_seq) do
    {messages, next_cursor} =
      Chats.messages_after(me.id, peer.id, epoch, after_seq, @max_page_size)

    %{messages: Enum.map(messages, &serialize_message(&1, me.id)), next_cursor: next_cursor}
  end

  def fetch_messages(_me, _peer, _params), do: %{error: "invalid"}

  defp send_reply({:ok, message}) do
    Events.broadcast_new_message(message)
    sent_reply(message)
  end

  defp send_reply({:duplicate, message}), do: sent_reply(message)
  defp send_reply({:error, {:stale_epoch, epoch}}), do: %{error: "stale_epoch", epoch: epoch}
  defp send_reply({:error, reason}), do: %{error: to_string(reason)}

  defp sent_reply(message) do
    %{id: message.id, seq: message.seq, epoch: message.epoch, client_nonce: message.client_nonce}
  end

  # The known key can lag behind the store (e.g. another device published the
  # identity after this socket connected): re-read it before rejecting a send as
  # superseded.
  defp refresh_identity_key(_me, key, key) when is_binary(key), do: key
  defp refresh_identity_key(me, _known, _claimed), do: PreKeyStore.identity_key(me.id)
end
