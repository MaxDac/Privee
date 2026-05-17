defmodule Privee.MessageFixtures do
  @moduledoc """
  This module defines test helpers for creating `Message` entities.
  """

  alias Privee.Sessions.Message

  import Privee.SessionsFixtures

  def valid_message_attributes(attrs \\ %{}) do
    attrs =
      attrs
      |> check_message_from()
      |> check_message_to()

    Enum.into(attrs, %{
      ciphertext: "encrypted_content_base64",
      header: ~s({"ratchetKey":"abc","n":0,"pn":0})
    })
  end

  def message_fixture(attrs \\ %{}) do
    valid_attributes = valid_message_attributes(attrs)

    %Message{
      from: valid_attributes.from,
      to: valid_attributes.to,
      ciphertext: valid_attributes.ciphertext,
      header: valid_attributes.header
    }
  end

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
