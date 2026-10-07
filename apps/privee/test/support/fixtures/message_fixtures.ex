defmodule Privee.MessageFixtures do
  @moduledoc """
  This module defines test helpers for creating `Message` entities.
  """

  alias Privee.Sessions.Message

  import Privee.SessionsFixtures

  def valid_message_attributes(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> check_message_from()
      |> check_message_to()

    Enum.into(attrs, %{
      type: 1,
      body: Base.encode64("ciphertext-" <> Ecto.UUID.generate()),
      client_nonce: unique_nonce(),
      sender_session_name: "sender"
    })
  end

  def message_fixture(attrs \\ %{}) do
    struct!(Message, valid_message_attributes(attrs))
  end

  def unique_nonce, do: Ecto.UUID.generate()

  defp check_message_from(%{from: from} = attrs) when not is_nil(from), do: attrs

  defp check_message_from(attrs) do
    %{id: from_id} = session_fixture(%{session_name: Ecto.UUID.generate()})
    Map.put(attrs, :from, from_id)
  end

  defp check_message_to(%{to: to} = attrs) when not is_nil(to), do: attrs

  defp check_message_to(attrs) do
    %{id: to_id} = session_fixture(%{session_name: Ecto.UUID.generate()})
    Map.put(attrs, :to, to_id)
  end
end
