defmodule Privee.Sessions.Message do
  @moduledoc """
  Represents a single message in a chat session.
  Purposefully, the message is an embedded entity, as it will not be saved in the
  database.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Privee.Sessions.Message
  alias Privee.Sessions.Session

  embedded_schema do
    field :text, :string

    belongs_to :from, Session
    belongs_to :to, Session
  end

  @doc false
  def changeset(%Message{} = message, attrs) do
    message
    |> cast(attrs, [:text, :from, :to])
    |> validate_required([:text, :from, :to])
    |> foreign_key_constraint(:from, name: :fk_message_from)
    |> foreign_key_constraint(:to, name: :fk_message_to)
  end
end
