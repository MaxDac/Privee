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
    * `text_from` - The original text of the message.
    * `text_to` - The translated or target text of the message.
    * `from` - The sender's identifier (non-negative integer).
    * `to` - The recipient's identifier or name (string).
    * `in_thread` - Indicates if the message is part of a thread, i.e. if the 
    *   sender/receiver is the same for all the messages (boolean).
    * `sender_session_name` - The name of the sender's session (string).
  """
  @type t :: %__MODULE__{
          text_from: String.t(),
          text_to: String.t(),
          from: non_neg_integer(),
          to: non_neg_integer(),
          in_thread: boolean(),
          sender_session_name: String.t()
        }

  embedded_schema do
    field :text_from, :string
    field :text_to, :string
    field :from, :id
    field :to, :id
    field :in_thread, :boolean, default: false
    # Added to simplify notification handling
    field :sender_session_name, :string
  end

  @doc false
  def changeset(%Message{} = message, attrs) do
    message
    |> cast(attrs, [:text_from, :text_to, :from, :to, :sender_session_name])
    |> validate_required([:text_from, :text_to, :from, :to, :sender_session_name])
  end
end
