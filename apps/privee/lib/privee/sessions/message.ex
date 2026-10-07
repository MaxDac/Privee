defmodule Privee.Sessions.Message do
  @moduledoc """
  Represents a single end-to-end encrypted message in a chat session.
  The message is an embedded entity: it is never saved in the database, only in
  the ephemeral `Privee.Chats` storage.

  Only `type`, `body` and `client_nonce` come from the client. Every other field
  is set by the server.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Privee.Sessions.Message

  # libsignal CiphertextMessageType: 2 = Whisper (SignalMessage), 3 = PreKey.
  @message_types [2, 3]
  @max_body_bytes 16_384

  @typedoc """
    * `id` - Server-assigned message id (UUID).
    * `seq` - Server-assigned ordering value, meaningful within `{conversation, epoch}`.
    * `epoch` - Conversation epoch the message belongs to.
    * `client_nonce` - Client-generated idempotency key.
    * `from` / `to` - Sender / recipient session ids.
    * `sender_session_name` - Sender session name (for notifications).
    * `type` - Signal message type (2 or 3).
    * `body` - Base64 encoded Signal ciphertext.
    * `in_thread` - UI flag: same sender as the previous message.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          seq: integer() | nil,
          epoch: String.t() | nil,
          client_nonce: String.t() | nil,
          from: non_neg_integer() | nil,
          to: non_neg_integer() | nil,
          sender_session_name: String.t() | nil,
          type: 2 | 3 | nil,
          body: String.t() | nil,
          in_thread: boolean()
        }

  @primary_key false
  embedded_schema do
    field :id, :string
    field :seq, :integer
    field :epoch, :string
    field :client_nonce, :string
    field :from, :id
    field :to, :id
    field :sender_session_name, :string
    field :type, :integer
    field :body, :string
    field :in_thread, :boolean, default: false
  end

  @doc """
  Casts the client-provided fields only. `from`, `to` and `sender_session_name`
  must already be set on the struct by the server.
  """
  def changeset(%Message{} = message, attrs) do
    message
    |> cast(attrs, [:type, :body, :client_nonce])
    |> validate_required([:type, :body, :client_nonce, :from, :to, :sender_session_name])
    |> validate_inclusion(:type, @message_types)
    |> validate_length(:body, max: div(@max_body_bytes * 4, 3) + 4)
    |> validate_change(:body, fn :body, body ->
      case Base.decode64(body) do
        {:ok, _} -> []
        :error -> [body: "must be base64 encoded"]
      end
    end)
    |> validate_length(:client_nonce, min: 16, max: 64)
    |> validate_format(:client_nonce, ~r/^[A-Za-z0-9-]+$/)
    |> validate_distinct_parties()
  end

  defp validate_distinct_parties(changeset) do
    if get_field(changeset, :from) == get_field(changeset, :to) do
      add_error(changeset, :to, "cannot be the sender")
    else
      changeset
    end
  end
end
