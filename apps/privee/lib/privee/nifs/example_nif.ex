defmodule Privee.Nifs.ExampleNif do
  @moduledoc """
  Documentation for `ExampleNif`.
  """

  @on_load :load_nif

  @dialyzer {:nowarn_function, load_nif: 0}
  @dialyzer {:nowarn_function, nif_add: 2}

  require Logger

  defp nif_path do
    environment = System.get_env("MIX_ENV")

    if environment == "prod",
      do: "../nifs/libexample_nif",
      else: "../../nifs/zig-out/lib/libexample_nif"
  end

  @doc """
  This function loads the NIF.
  It has been previously called during module load.
  """
  def load_nif do
    path = nif_path()
    Logger.info("NIF path: #{path}")
    :erlang.load_nif(path, 0)
  end

  @doc """
  The NIF interface itself. At runtime, this function will be substituted with the
  NIF call to the Zig function, configured in the project.
  """
  def nif_add(_a, _b), do: :erlang.nif_error(:nif_not_loaded)
end
