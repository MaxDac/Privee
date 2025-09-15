defmodule Privee.Sessions.Session do
  @moduledoc """
  The session schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          session_name: String.t(),
          recovery_phrase: String.t(),
          hashed_recovery_phrase: String.t(),
          public_key: String.t(),
          is_quick: boolean(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "sessions" do
    field :session_name, :string
    field :recovery_phrase, :string, virtual: true, redact: true
    field :hashed_recovery_phrase, :string, redact: true
    field :public_key, :string, redact: true
    field :is_quick, :boolean

    timestamps()
  end

  @doc """
  A changeset for registration.

  It is important to validate the length of the session name.
  Otherwise databases may truncate the session name without warnings, which
  could lead to unpredictable or insecure behaviour. Long sessions may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_recovery_phrase` - Hashes the recovery phrase so it can be stored securely
      in the database and ensures the recovery_phrase field is cleared to prevent
      leaks in the logs. If recovery phrase hashing is not needed and clearing the
      recovery phrase field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_recovery_phrase` - Validates the uniqueness of the recovery phrase,
      in case you don't want to validate the uniqueness of the recovery phrase (like
      when using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(session, attrs, opts \\ []) do
    session
    |> cast(attrs, [:session_name, :recovery_phrase, :public_key, :is_quick])
    |> validate_session_name(opts)
    |> validate_recovery_phrase(opts)
    |> validate_public_key(opts)
  end

  @doc """
  Validates the session name format.
  """
  def validate_session_name_format(changeset) do
    changeset
    |> validate_required([:session_name])
    |> validate_length(:session_name, min: 24, max: 72)
    |> validate_format(:session_name, ~r/^[a-zA-Z0-9-]+$/,
      message: "must contain only alphanumeric characters and hyphens"
    )
  end

  defp validate_session_name(changeset, opts) do
    changeset
    |> validate_session_name_format()
    |> validate_unique_session_name(opts)
  end

  defp validate_recovery_phrase(changeset, opts) do
    is_quick = get_field(changeset, :is_quick) || false

    if is_quick do
      validate_quick_session_recovery_phrase(changeset, opts)
    else
      validate_regular_session_recovery_phrase(changeset, opts)
    end
  end

  defp validate_quick_session_recovery_phrase(changeset, _opts) do
    recovery_phrase = get_field(changeset, :recovery_phrase)

    if recovery_phrase && recovery_phrase != "" do
      add_error(changeset, :recovery_phrase, "must be empty for quick sessions")
    else
      changeset
    end
  end

  defp validate_regular_session_recovery_phrase(changeset, opts) do
    changeset
    |> validate_required([:recovery_phrase])
    |> validate_length(:recovery_phrase, min: 24, max: 160)
    |> validate_format(:recovery_phrase, ~r/^[a-zA-Z\s\.\,\;\:\!\?]+$/,
      message: "must contain only alphabetic characters and punctuation"
    )
    |> maybe_hash_recovery_phrase(opts)
  end

  defp maybe_hash_recovery_phrase(changeset, opts) do
    hash_recovery_phrase? = Keyword.get(opts, :hash_recovery_phrase, true)
    recovery_phrase = get_change(changeset, :recovery_phrase)

    if hash_recovery_phrase? && recovery_phrase && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:recovery_phrase, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_recovery_phrase, Bcrypt.hash_pwd_salt(recovery_phrase))
      |> delete_change(:recovery_phrase)
    else
      changeset
    end
  end

  defp validate_public_key(changeset, _opts) do
    validate_required(changeset, :public_key, message: "The public key has not been generated")
  end

  defp validate_unique_session_name(changeset, _opts) do
    changeset
    |> unsafe_validate_unique(:session_name, Privee.Repo)
    |> unique_constraint(:session_name)
  end

  @doc """
  Verifies the recovery phrase.

  If there is no recovery phrase or the session doesn't have a recovery phrase, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_recovery_phrase?(
        %Privee.Sessions.Session{hashed_recovery_phrase: hashed_recovery_phrase},
        recovery_phrase
      )
      when is_binary(hashed_recovery_phrase) and byte_size(recovery_phrase) > 0 do
    Bcrypt.verify_pass(recovery_phrase, hashed_recovery_phrase)
  end

  def valid_recovery_phrase?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current session otherwise adds an error to the changeset.
  """
  def validate_current_recovery_phrase(changeset, recovery_phrase) do
    if valid_recovery_phrase?(changeset.data, recovery_phrase) do
      changeset
    else
      add_error(changeset, :current_recovery_phrase, "is not valid")
    end
  end
end
