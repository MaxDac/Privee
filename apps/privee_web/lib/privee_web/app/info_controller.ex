defmodule PriveeWeb.App.InfoController do
  @moduledoc """
  `GET /api/app/info` - unauthenticated description of this Privee instance.

  Clients call it to check that a user-supplied URL points to a compatible
  Privee server before using it; see `docs/client-api.md`.
  """

  use PriveeWeb, :controller

  alias PriveeWeb.Instance

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(Instance.info())
  end
end
