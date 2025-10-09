defmodule BautaWeb.ErrorJSONTest do
  use BautaWeb.ConnCase, async: true

  test "renders 404" do
    assert BautaWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert BautaWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
