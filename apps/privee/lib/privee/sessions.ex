defmodule Privee.Sessions do
  @moduledoc """
  The Sessions context.
  """

  import Ecto.Query, warn: false

  alias Plug.Session

  alias Privee.Repo
  alias Privee.Sessions.PriveeForm
  alias Privee.Sessions.{Message, PriveeForm, Session, SessionToken}

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

  @doc """
  Gets a single session.

  Returns nil if the session does not exist.

  ## Examples

      iex> get_session(123)
      %Session{}

      iex> get_session(456)
      nil

  """
  def get_session(id), do: Repo.get(Session, id)

  @doc """
  Gets a single session using its session name.

  Returns nil if the session does not exist.

  ## Examples

      iex> get_session_by_session_name("some-existent-session-name")
      %Session{}

      iex> get_session_by_session_name("some-non-existent-session-name")
      nil

  """
  def get_session_by_session_name(session_name),
    do: Repo.get_by(Session, session_name: session_name)

  @doc """
  Generates a new session name available, i.e. non currently existing on the database.
  """
  def generate_new_available_session_name do
    new_session_name = Ecto.UUID.generate()

    if session_name_exists?(new_session_name) do
      generate_new_available_session_name()
    else
      new_session_name
    end
  end

  defp session_name_exists?(session_name) do
    Session
    |> from()
    |> where([s], s.session_name == ^session_name)
    |> Repo.exists?()
  end

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
    Session.registration_changeset(session, attrs, hash_recovery_phrase: false)
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

  #
  # Quick sessions management
  #

  @doc """
  Checks whether the session is a quick session, and it has already been logged into.
  """
  def is_session_valid(session)
  def is_session_valid(%{is_quick: true, has_logged: true}), do: false
  def is_session_valid(_), do: true

  @doc """
  Marks the session as already logged.
  """
  def mark_session_as_logged(session)


  def mark_session_as_logged(%{id: session_id} = session) do
    case session |> Session.update_has_logged_changeset(true) |> Repo.update() do
      {:ok, _} ->
        {:ok, get_session!(session_id)}

      error ->
        error
    end
  end

  def mark_session_as_logged(_) do
    {:error, "Invalid session"}
  end

  #
  # Privee form
  #

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.

  ## Examples

      iex> change_privee_form(privee_form)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_privee_form(%PriveeForm{} = privee_form, attrs \\ %{}) do
    privee_form
    |> PriveeForm.changeset(attrs)
    |> validate_session_name_exists()
  end

  defp validate_session_name_exists(changeset) do
    Ecto.Changeset.validate_change(changeset, :session_name, fn field, value ->
      if session_name_exists?(value),
        do: [],
        else: [{field, "The session name does not exist"}]
    end)
  end

  @doc """
  Provides the changeset for the message.
  """
  def change_message(%Message{} = message, attrs \\ %{}) do
    message
    |> Message.changeset(attrs)
  end
end
