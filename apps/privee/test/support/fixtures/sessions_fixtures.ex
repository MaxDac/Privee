defmodule Privee.SessionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Privee.Sessions` context.
  """

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

  def extract_session_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
