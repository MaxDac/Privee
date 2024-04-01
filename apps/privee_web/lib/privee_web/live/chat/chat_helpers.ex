defmodule PriveeWeb.Chat.ChatHelpers do
  @moduledoc """
  A collection of helpers for the representation of the chat messages.
  """

  @doc """
  Parses the messages, adding a field that would tell the chat template whether
  the message is part of a thread of messages from the same user or not.

  The message with the same user will have the field `in_thread` equal to `true`,
  `false` otherwise.
  """
  def parse_messages(messages),
    do:
      messages
      |> Enum.reverse()
      |> parse_messages([], 0)

  @doc """
  Adds a message to the previous stream of messages already present in the chat.
  Having that this message will be added to a stream, this function will return only
  the last message, with the right properties associated.
  This function will be used when receiving a notification with another chat.
  """
  def add_message(message, previous_messages) do
    case {message, previous_messages} do
      {message, []} ->
        Map.put(message, :id, 0)

      {%{to: new_message_to}, [%{id: last_id, to: last_message_to} | _]} ->
        message
        |> Map.put(:in_thread, new_message_to == last_message_to)
        |> Map.put(:id, last_id + 1)
    end
  end

  defp parse_messages(messages, acc, index)

  defp parse_messages([], acc, _), do: acc

  defp parse_messages([message | [next | _] = rest], acc, index),
    do:
      parse_messages(
        rest,
        [
          message
          |> Map.put(:in_thread, message.to == next.to)
          |> Map.put(:id, index)
          | acc
        ],
        index + 1
      )

  defp parse_messages([message | rest], acc, index),
    do:
      parse_messages(
        rest,
        [
          message
          |> Map.put(:in_thread, false)
          |> Map.put(:id, index)
          | acc
        ],
        index + 1
      )
end
