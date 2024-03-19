defmodule Privee.Sessions.Message do
  @moduledoc """
  Represents a single message in a chat session.
  Purposefully, the message is an embedded entity, as it will not be saved in the
  database.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Privee.Sessions.Message

  @type t :: %__MODULE__{
          text: non_neg_integer(),
          from: non_neg_integer(),
          to: String.t(),
          in_thread: boolean(),
          sender_session_name: String.t()
        }

  embedded_schema do
    field :text, :string
    field :from, :id
    field :to, :id
    field :in_thread, :boolean, default: false
    # Added to simplify notification handling
    field :sender_session_name, :string
  end

  @doc false
  def changeset(%Message{} = message, attrs) do
    message
    |> cast(attrs, [:text, :from, :to, :sender_session_name])
    |> validate_required([:text, :from, :to, :sender_session_name])
  end
end
