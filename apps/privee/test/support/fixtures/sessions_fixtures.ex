defmodule Privee.SessionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Privee.Sessions` context.
  """

  def unique_session_email, do: "session#{System.unique_integer()}@example.com"
  def valid_session_password, do: "hello world!"

  def valid_session_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_session_email(),
      password: valid_session_password()
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
