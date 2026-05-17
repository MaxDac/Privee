defmodule Privee.SessionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Privee.Sessions` context.
  """

  alias Privee.Sessions.Session

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
    has_logged_value = Map.get(attrs, :has_logged)
    attrs_without_has_logged = Map.delete(attrs, :has_logged)

    {:ok, session} =
      attrs_without_has_logged
      |> valid_session_attributes()
      |> Privee.Sessions.register_session()

    # Update has_logged if specified (for testing purposes)
    case has_logged_value do
      nil ->
        session

      value when is_boolean(value) ->
        session
        |> Session.update_has_logged_changeset(value)
        |> Privee.Repo.update!()
    end
  end

  def valid_quick_session_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      session_name: unique_session_name(),
      is_quick: true
    })
  end

  def quick_session_fixture(attrs \\ %{}) do
    has_logged_value = Map.get(attrs, :has_logged)
    attrs_without_has_logged = Map.delete(attrs, :has_logged)

    {:ok, session} =
      attrs_without_has_logged
      |> valid_quick_session_attributes()
      |> Privee.Sessions.register_session()

    # Update has_logged if specified (for testing purposes)
    case has_logged_value do
      nil ->
        session

      value when is_boolean(value) ->
        session
        |> Session.update_has_logged_changeset(value)
        |> Privee.Repo.update!()
    end
  end
end
