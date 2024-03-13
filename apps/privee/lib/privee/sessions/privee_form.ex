defmodule Privee.Sessions.PriveeForm do
  @moduledoc """
  Represents the 
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Privee.Sessions.PriveeForm
  alias Privee.Sessions.Session

  @type t :: %__MODULE__{
    session_name: String.t()
  }

  embedded_schema do 
    field :session_name, :string
  end

  @doc false
  def changeset(%PriveeForm{} = privee_form, attrs) do
    privee_form
    |> cast(attrs, [:session_name])
    |> Session.validate_session_name_format()
  end
end
