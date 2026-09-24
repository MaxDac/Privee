defmodule PriveeWeb.PreKeyRouteTest do
  use PriveeWeb.ConnCase, async: true

  test "the unauthenticated prekey API is gone", %{conn: conn} do
    conn = post(conn, "/api/prekeys/1", %{})
    assert conn.status == 404
  end
end
