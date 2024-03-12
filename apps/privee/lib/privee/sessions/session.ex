defmodule Privee.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: non_neg_integer(),

          session_name: String.t(),
          hashed_session_name: String.t(),
          recovery_phrase: String.t(),
          confirmed_at: NaiveDateTime.t(),

          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "sessions" do
    field :session_name, :string, virtual: true, redact: true
    field :hashed_session_name, :string, redact: true
    field :recovery_phrase, :string
    field :confirmed_at, :naive_datetime

    timestamps()
  end

  @doc """
  A session_name changeset for registration.

  It is important to validate the length of the session name.
  Otherwise databases may truncate the session name without warnings, which
  could lead to unpredictable or insecure behaviour. Long sessions may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_session_name` - Hashes the session name so it can be stored securely
      in the database and ensures the session name field is cleared to prevent
      leaks in the logs. If session name hashing is not needed and clearing the
      session name field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_session_name` - Validates the uniqueness of the session name, in case
      you don't want to validate the uniqueness of the session name (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(session, attrs, opts \\ []) do
    session
    |> cast(attrs, [:session_name, :recovery_phrase])
    |> validate_session_name(opts)
    |> validate_recovery_phrase()
  end

  defp validate_session_name(changeset, opts) do
    changeset
    |> validate_required([:session_name])
    |> validate_length(:session_name, min: 24, max: 72)
    |> validate_format(:session_name, ~r/^[a-zA-Z0-9-]+$/, message: "must contain only alphanumeric characters and hyphens")
    |> maybe_hash_session_name(opts)
    |> validate_unique_session_name(opts)
  end

  defp validate_recovery_phrase(changeset) do
    changeset
    |> validate_required([:recovery_phrase])
    |> validate_length(:recovery_phrase, min: 24, max: 160)
    |> validate_format(:recovery_phrase, ~r/^[a-zA-Z\s\.\,\;\:\!\?]+$/, message: "must contain only alphabetic characters and punctuation")
  end

  defp maybe_hash_session_name(changeset, opts) do
    hash_session_name? = Keyword.get(opts, :hash_session_name, true)
    session_name = get_change(changeset, :session_name)

    if hash_session_name? && session_name && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:session_name, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_session_name, Bcrypt.hash_pwd_salt(session_name))
      |> delete_change(:session_name)
    else
      changeset
    end
  end

  defp validate_unique_session_name(changeset, opts) do
    hash_session_name? = Keyword.get(opts, :hash_session_name, true)
    if hash_session_name? do
      changeset
      |> unsafe_validate_unique(:hashed_session_name, Privee.Repo)
      |> unique_constraint(:hashed_session_name)
    else
      changeset
    end
  end

  @doc """
  A session changeset for changing the recovery_phrase.

  It requires the recovery_phrase to change otherwise an error is added.
  """
  def recovery_phrase_changeset(session, attrs) do
    session
    |> cast(attrs, [:recovery_phrase])
    |> validate_recovery_phrase()
    |> case do
      %{changes: %{recovery_phrase: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :recovery_phrase, "did not change")
    end
  end

  @doc """
  A session changeset for changing the session name.

  ## Options

    * `:hash_session name` - Hashes the session name so it can be stored securely
      in the database and ensures the session name field is cleared to prevent
      leaks in the logs. If session name hashing is not needed and clearing the
      session name field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def session_name_changeset(session, attrs, opts \\ []) do
    session
    |> cast(attrs, [:session_name])
    |> validate_confirmation(:session_name, message: "does not match session name")
    |> validate_session_name(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(session) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(session, confirmed_at: now)
  end

  @doc """
  Verifies the session name.

  If there is no session name or the session doesn't have a session name, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_session_name?(%Privee.Sessions.Session{hashed_session_name: hashed_session_name}, session_name)
      when is_binary(hashed_session_name) and byte_size(session_name) > 0 do
    Bcrypt.verify_pass(session_name, hashed_session_name)
  end

  def valid_session_name?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current session otherwise adds an error to the changeset.
  """
  def validate_current_session_name(changeset, session_name) do
    if valid_session_name?(changeset.data, session_name) do
      changeset
    else
      add_error(changeset, :current_session_name, "is not valid")
    end
  end
end
