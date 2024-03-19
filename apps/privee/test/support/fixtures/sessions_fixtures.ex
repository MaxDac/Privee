defmodule Privee.SessionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Privee.Sessions` context.
  """

  alias Privee.Sessions.Message

  def unique_session_name, do: "636e6e5a-080a-48b3-8db2-2fd5fde039df"
  def generate_new_unique_session_name, do: Ecto.UUID.generate()
  def session_recovery_phrase, do: "The quick brown fox jumps over the lazy dog"

  def valid_session_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      session_name: unique_session_name(),
      recovery_phrase: session_recovery_phrase()
    })
  end

  def session_fixture(attrs \\ %{}) do
    {:ok, session} =
      attrs
      |> valid_session_attributes()
      |> Privee.Sessions.register_session()

    session
  end

  def valid_message_attributes(attrs \\ %{}) do
    attrs =
      attrs
      |> check_message_from()
      |> check_message_to()

    Enum.into(attrs, %{
      text: "Some text"
    })
  end

  def message_fixture(attrs \\ %{}) do
    valid_attributes = valid_message_attributes(attrs)

    %Message{
      from: valid_attributes.from,
      to: valid_attributes.to,
      text: valid_attributes.text
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
