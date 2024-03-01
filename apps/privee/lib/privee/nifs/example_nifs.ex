defmodule Privee.Nifs.ExampleNifs do
  @moduledoc """
  Documentation for `ExampleNif`.
  """

  @on_load :load_nif

  @doc """
  This function loads the NIF.
  It has been previously called during module load.
  """
  def load_nif do
    :erlang.load_nif("./nifs/zig-out/lib/libexample_nif", 0)
  end

  @doc """
  The NIF interface itself. At runtime, this function will be substituted with the
  NIF call to the Zig function, configured in the project.
  """
  def nif_add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
