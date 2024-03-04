defmodule Nifs.ExampleNifTest do
  use Privee.DataCase

  alias Privee.Nifs.ExampleNif

  test "2 + 2 = 4" do
    result = ExampleNif.nif_add(2, 2)
    assert result == 4
  end
end
