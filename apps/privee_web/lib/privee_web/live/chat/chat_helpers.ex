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

  defp parse_messages(messages, acc)

  defp parse_messages([], acc), do: acc

  defp parse_messages([message | [next | _] = rest], acc),
    do: parse_messages(rest, [Map.put(message, :in_thread, message.to == next.to) | acc])

  defp parse_messages([message | rest], acc),
    do: parse_messages(rest, [Map.put(message, :in_thread, false) | acc])
end
