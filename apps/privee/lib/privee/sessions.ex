defmodule Privee.Sessions do
  @moduledoc """
  The Sessions context.
  """

  import Ecto.Query, warn: false

  alias Privee.Repo
  alias Privee.Sessions.{Session, SessionToken}

  @doc """
  Gets a session by the recovery phrase and the password.

  ## Examples

      iex> get_session_by_session_name_and_phrase("Some phrase", "valid-session")
      %Session{}

      iex> get_session_by_session_name_and_phrase("Some phrase", "invalid-session")
      nil

  """
  def get_session_by_session_name_and_phrase(session_name, recovery_phrase)
      when is_binary(session_name) and is_binary(recovery_phrase) do
    session = Repo.get_by(Session, session_name: session_name)

    if Session.valid_recovery_phrase?(session, recovery_phrase), do: session
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.

  ## Examples

      iex> get_session!(123)
      %Session{}

      iex> get_session!(456)
      ** (Ecto.NoResultsError)

  """
  def get_session!(id), do: Repo.get!(Session, id)

  ## Session registration

  @doc """
  Registers a session.

  ## Examples

      iex> register_session(%{field: value})
      {:ok, %Session{}}

      iex> register_session(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_session(attrs) do
    %Session{}
    |> Session.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.

  ## Examples

      iex> change_session_registration(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session_registration(%Session{} = session, attrs \\ %{}) do
    Session.registration_changeset(session, attrs, hash_session_name: false)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_session_token(session) do
    {token, session_token} = SessionToken.build_session_token(session)
    Repo.insert!(session_token)
    token
  end

  @doc """
  Gets the session with the given signed token.
  """
  def get_session_by_session_token(token) do
    {:ok, query} = SessionToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(SessionToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
