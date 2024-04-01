defmodule PriveeWeb.Chat.ChatHelpers do
  @moduledoc """
  A collection of helpers for the representation of the chat messages.
  """

  @doc """
  Parses the messages, adding a field that would tell the chat template whether
  the message is part of a thread of messages from the same user or not.

  The message with the same user will have the field `in_thread` equal to `true`,
  `false` otherwise.

  The return value is a tuple containing the last message and the parsed messages.
  """
  def parse_messages(messages) do
    parsed =
      messages
      |> Enum.with_index()
      |> Enum.reverse()
      |> parse_messages([])

    {List.last(parsed), parsed}
  end

  defp parse_messages(messages, acc)

  defp parse_messages([], acc), do: acc

  defp parse_messages([{message, index} | [{next, _} | _] = rest], acc),
    do:
      parse_messages(
        rest,
        [
          message
          |> Map.put(:in_thread, message.to == next.to)
          |> Map.put(:id, index)
          | acc
        ]
      )

  defp parse_messages([{message, index} | rest], acc),
    do:
      parse_messages(
        rest,
        [
          message
          |> Map.put(:in_thread, false)
          |> Map.put(:id, index)
          | acc
        ]
      )

  @doc """
  Adds a message to the previous stream of messages already present in the chat.
  Having that this message will be added to a stream, this function will return only
  the last message, with the right properties associated.
  This function will be used when receiving a notification with another chat.
  """
  def add_message(message, last_message) do
    IO.inspect last_message, label: "last_message"
    case {message, last_message} do
      {message, nil} ->
        Map.put(message, :id, 0)

      {%{to: new_message_to}, %{id: last_id, to: last_message_to}} ->
        message
        |> Map.put(:in_thread, new_message_to == last_message_to)
        |> Map.put(:id, last_id + 1)
    end
  end
end
