defmodule BautaWeb.PageController do
  use BautaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
