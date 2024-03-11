defmodule Privee.Sessions do
  @moduledoc """
  The Sessions context.
  """

  import Ecto.Query, warn: false
  alias Privee.Repo

  alias Privee.Sessions.{Session, SessionToken, SessionNotifier}

  ## Database getters

  @doc """
  Gets a session by email.

  ## Examples

      iex> get_session_by_email("foo@example.com")
      %Session{}

      iex> get_session_by_email("unknown@example.com")
      nil

  """
  def get_session_by_email(email) when is_binary(email) do
    Repo.get_by(Session, email: email)
  end

  @doc """
  Gets a session by email and password.

  ## Examples

      iex> get_session_by_email_and_password("foo@example.com", "correct_password")
      %Session{}

      iex> get_session_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_session_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    session = Repo.get_by(Session, email: email)
    if Session.valid_password?(session, password), do: session
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
    Session.registration_changeset(session, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the session email.

  ## Examples

      iex> change_session_email(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session_email(session, attrs \\ %{}) do
    Session.email_changeset(session, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_session_email(session, "valid password", %{email: ...})
      {:ok, %Session{}}

      iex> apply_session_email(session, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_session_email(session, password, attrs) do
    session
    |> Session.email_changeset(attrs)
    |> Session.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the session email using the given token.

  If the token matches, the session email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_session_email(session, token) do
    context = "change:#{session.email}"

    with {:ok, query} <- SessionToken.verify_change_email_token_query(token, context),
         %SessionToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(session_email_multi(session, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp session_email_multi(session, email, context) do
    changeset =
      session
      |> Session.email_changeset(%{email: email})
      |> Session.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, changeset)
    |> Ecto.Multi.delete_all(:tokens, SessionToken.by_session_and_contexts_query(session, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given session.

  ## Examples

      iex> deliver_session_update_email_instructions(session, current_email, &url(~p"/sessions/settings/confirm_email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_session_update_email_instructions(%Session{} = session, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, session_token} = SessionToken.build_email_token(session, "change:#{current_email}")

    Repo.insert!(session_token)
    SessionNotifier.deliver_update_email_instructions(session, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the session password.

  ## Examples

      iex> change_session_password(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session_password(session, attrs \\ %{}) do
    Session.password_changeset(session, attrs, hash_password: false)
  end

  @doc """
  Updates the session password.

  ## Examples

      iex> update_session_password(session, "valid password", %{password: ...})
      {:ok, %Session{}}

      iex> update_session_password(session, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_session_password(session, password, attrs) do
    changeset =
      session
      |> Session.password_changeset(attrs)
      |> Session.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, changeset)
    |> Ecto.Multi.delete_all(:tokens, SessionToken.by_session_and_contexts_query(session, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_session_session_token(session) do
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
  def delete_session_session_token(token) do
    Repo.delete_all(SessionToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given session.

  ## Examples

      iex> deliver_session_confirmation_instructions(session, &url(~p"/sessions/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_session_confirmation_instructions(confirmed_session, &url(~p"/sessions/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_session_confirmation_instructions(%Session{} = session, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if session.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, session_token} = SessionToken.build_email_token(session, "confirm")
      Repo.insert!(session_token)
      SessionNotifier.deliver_confirmation_instructions(session, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a session by the given token.

  If the token matches, the session account is marked as confirmed
  and the token is deleted.
  """
  def confirm_session(token) do
    with {:ok, query} <- SessionToken.verify_email_token_query(token, "confirm"),
         %Session{} = session <- Repo.one(query),
         {:ok, %{session: session}} <- Repo.transaction(confirm_session_multi(session)) do
      {:ok, session}
    else
      _ -> :error
    end
  end

  defp confirm_session_multi(session) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, Session.confirm_changeset(session))
    |> Ecto.Multi.delete_all(:tokens, SessionToken.by_session_and_contexts_query(session, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given session.

  ## Examples

      iex> deliver_session_reset_password_instructions(session, &url(~p"/sessions/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_session_reset_password_instructions(%Session{} = session, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, session_token} = SessionToken.build_email_token(session, "reset_password")
    Repo.insert!(session_token)
    SessionNotifier.deliver_reset_password_instructions(session, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the session by reset password token.

  ## Examples

      iex> get_session_by_reset_password_token("validtoken")
      %Session{}

      iex> get_session_by_reset_password_token("invalidtoken")
      nil

  """
  def get_session_by_reset_password_token(token) do
    with {:ok, query} <- SessionToken.verify_email_token_query(token, "reset_password"),
         %Session{} = session <- Repo.one(query) do
      session
    else
      _ -> nil
    end
  end

  @doc """
  Resets the session password.

  ## Examples

      iex> reset_session_password(session, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %Session{}}

      iex> reset_session_password(session, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_session_password(session, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:session, Session.password_changeset(session, attrs))
    |> Ecto.Multi.delete_all(:tokens, SessionToken.by_session_and_contexts_query(session, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _} -> {:error, changeset}
    end
  end
end
