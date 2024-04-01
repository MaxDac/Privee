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
      |> parse_messages([])

  @doc """
  Adds a message to the previous list of messages already present in the chat.
  This function will be used when receiving a notification with another chat.
  """
  def add_message(message, previous_messages) do
    parse_messages([message | Enum.reverse(previous_messages)], [])
  end

  defp parse_messages(messages, acc, index \\ 0)

  defp parse_messages([], acc, _), do: acc

  defp parse_messages([message | [next | _] = rest], acc, index),
    do:
      parse_messages(
        rest,
        [
          message
          |> Map.put(:in_thread, message.to == next.to)
          |> Map.put(:index, index)
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
          |> Map.put(:index, index)
          | acc
        ],
        index + 1
      )
end
