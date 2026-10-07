defmodule PriveeWeb.Chat.ChatHelpers do
  @moduledoc """
  A collection of helpers for the representation of the chat messages.
  """

  alias Privee.Sessions.Message

  @doc """
  Marks each message of an ascending list with `in_thread: true` when it has the
  same sender as the previous message. Server-assigned ids are preserved.

  Returns `{last_message, messages}`.
  """
  @spec parse_messages(list(Message.t())) :: {Message.t() | nil, list(Message.t())}
  def parse_messages(messages) do
    {parsed, last} =
      Enum.map_reduce(messages, nil, fn message, previous ->
        parsed = add_message(message, previous)
        {parsed, parsed}
      end)

    {last, parsed}
  end

  @doc """
  Returns `message` marked as part of a thread when `last_message` has the same
  sender.
  """
  @spec add_message(Message.t(), Message.t() | nil) :: Message.t()
  def add_message(message, nil), do: %{message | in_thread: false}

  def add_message(%{from: from} = message, %{from: last_from}),
    do: %{message | in_thread: from == last_from}

  @doc "DOM id of the stream entry for `message`."
  def message_dom_id(%{id: id}), do: "msg-#{id}"

  @doc """
  Serializes a message for the client. The client nonce is only disclosed to
  its sender.
  """
  @spec serialize_message(Message.t(), non_neg_integer()) :: map()
  def serialize_message(%Message{} = message, current_session_id) do
    outgoing? = message.from == current_session_id

    %{
      id: message.id,
      seq: message.seq,
      epoch: message.epoch,
      type: message.type,
      body: message.body,
      direction: if(outgoing?, do: "out", else: "in"),
      client_nonce: if(outgoing?, do: message.client_nonce)
    }
  end
end
