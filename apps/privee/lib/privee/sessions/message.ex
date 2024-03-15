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
          to: String.t()
        }

  embedded_schema do
    field :text, :string
    field :from, :id
    field :to, :id
  end

  @doc false
  def changeset(%Message{} = message, attrs) do
    message
    |> cast(attrs, [:text, :from, :to])
    |> validate_required([:text, :from, :to])
  end
end
