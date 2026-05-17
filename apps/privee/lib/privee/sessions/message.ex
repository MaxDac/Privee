defmodule Privee.Sessions.Message do
  @moduledoc """
  Represents a single message in a chat session.
  Purposefully, the message is an embedded entity, as it will not be saved in the
  database.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Privee.Sessions.Message

  @doc """
  Represents a message session.

  Fields:
    * `ciphertext` - The encrypted message content (Signal Protocol ciphertext).
    * `header` - The Signal Protocol message header (for ratchet state).
    * `from` - The sender's identifier (non-negative integer).
    * `to` - The recipient's identifier or name (string).
    * `in_thread` - Indicates if the message is part of a thread, i.e. if the 
    *   sender/receiver is the same for all the messages (boolean).
    * `sender_session_name` - The name of the sender's session (string).
  """
  @type t :: %__MODULE__{
          ciphertext: String.t(),
          header: String.t(),
          from: non_neg_integer(),
          to: non_neg_integer(),
          in_thread: boolean(),
          sender_session_name: String.t()
        }

  embedded_schema do
    field :ciphertext, :string
    field :header, :string
    field :from, :id
    field :to, :id
    field :in_thread, :boolean, default: false
    # Added to simplify notification handling
    field :sender_session_name, :string
  end

  @doc false
  def changeset(%Message{} = message, attrs) do
    message
    |> cast(attrs, [:ciphertext, :header, :from, :to, :sender_session_name])
    |> validate_required([:ciphertext, :header, :from, :to, :sender_session_name])
  end
end
