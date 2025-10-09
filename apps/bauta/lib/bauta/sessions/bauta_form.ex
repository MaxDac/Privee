defmodule Bauta.Sessions.BautaForm do
  @moduledoc """
  Represents the 
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Bauta.Sessions.BautaForm
  alias Bauta.Sessions.Session

  @type t :: %__MODULE__{
          session_name: String.t()
        }

  embedded_schema do
    field :session_name, :string
  end

  @doc false
  def changeset(%BautaForm{} = bauta_form, attrs) do
    bauta_form
    |> cast(attrs, [:session_name])
    |> Session.validate_session_name_format()
  end
end
