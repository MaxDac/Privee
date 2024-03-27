defmodule Privee.SessionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Privee.Sessions` context.
  """

  def unique_session_name, do: "636e6e5a-080a-48b3-8db2-2fd5fde039df"
  def generate_new_unique_session_name, do: Ecto.UUID.generate()

  def session_recovery_phrase, do: "The quick brown fox jumps over the lazy dog"

  def default_public_key,
    do: """
    0%C2%82%01%220%0A%06%09*%C2%86H%C2%86%C3%B7%0A%01%01%01%05%EF%BF%BD%03%C2%82%01%0F%EF%BF%BD0%C2%82%01%0A%02%C2%82%01%01%EF%BF%BD%C3%8C%C2%8C%C2%82%22%C3%B2%C3%8C%C3%95%C3%90%C3%8E%C3%BF%C2%AD%C3%AC9%C3%A5%C3%B78%07%C3%A8-%26%C3%92%C2%8F%C3%84%C2%B1%C3%A5O%C3%8A%2B%C2%8B%C3%B7%C3%B8%1Fg%C2%B1%C3%B6I%13TnA%C3%A7%C2%BA%C2%A1%C3%A3%C3%B2%C3%BB%C3%84-L%C3%A4fyNX%25%C3%9A%C2%9A%02%16%C3%A2%C3%8AQ%0AK%C2%BFL%C2%AB%C2%AD%C3%B5q%C3%BD%01V%3D%08%C2%91%26y%C2%B8%C2%B6%0F%C2%B0%17%C3%B7%C3%B1%C3%B1N%07%0B%C2%ABp%C2%8E%7B%C3%B8_NA%C3%B8C%C2%87%C3%AE%C3%BF%C2%82%0A*J%C2%90%C2%98%7C%C3%A7t%3E%2B%25%C3%BA%0A%C3%B6%C2%8DbXi%C2%87%26%C2%87%EF%BF%BD%C3%B3%C3%9C%C2%B7%C3%9AL%01%C2%8D%C3%92X%C3%96%C3%A8%C2%B8%C3%B3%C2%BF%5EC%C2%83e%C3%B0%C3%82-%C2%B4%C2%A1%C3%A4%19un%C2%89%C3%A0%C3%BE%C3%AD%25%C3%A0%3B%C3%A2%0F%28%C3%8E%21%C3%91%C3%99y%C3%A0%C3%AD%C3%AC+%07Il%C2%81%C2%80HD%C3%98%C3%8B%2C%C3%A4%C3%88%C3%92%C3%B0U%C3%8D6%C2%81%C2%A2PI%C2%8El9%C3%B3%C2%B8L+%193%C2%BC%C3%A3w%C3%84%C2%87G%C2%8D%C3%87c%C2%BF%C3%B0b%C2%948%3A%C2%A8%C2%B5%C2%BB%C2%B6F%C2%ADB%C3%A1c%17R%C3%A0c%1A%26%0C%7B%C3%9EY%C2%81%C3%8BPn%C3%87J%1E%C2%87z0%C3%9C%21%0A%C3%97L%C3%8Be7%C3%82%C3%9A%C2%8D%02%03%01%EF%BF%BD%01
    """

  def generate_new_unique_public_key, do: Ecto.UUID.generate()

  def valid_session_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      session_name: unique_session_name(),
      recovery_phrase: session_recovery_phrase(),
      public_key: default_public_key()
    })
  end

  def session_fixture(attrs \\ %{}) do
    {:ok, session} =
      attrs
      |> valid_session_attributes()
      |> Privee.Sessions.register_session()

    session
  end
end
