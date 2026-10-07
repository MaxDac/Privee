defmodule PriveeWeb.App.PushControllerTest do
  use PriveeWeb.ConnCase, async: true

  import Privee.SessionsFixtures

  alias Privee.Push
  alias Privee.Sessions
  alias PriveeWeb.App.AppAuth

  @endpoint_url "https://push.example.com/up/abc"

  setup %{conn: conn} do
    session = session_fixture()
    token = Sessions.generate_session_token(session)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> AppAuth.encode_token(token))

    %{conn: conn, session: session}
  end

  test "PUT /api/app/push registers the endpoint", %{conn: conn, session: session} do
    conn = put(conn, ~p"/api/app/push", %{endpoint: @endpoint_url})
    assert response(conn, 204)
    assert Push.endpoints(session.id) == [@endpoint_url]
  end

  test "PUT /api/app/push rejects invalid endpoints", %{conn: conn, session: session} do
    conn = put(conn, ~p"/api/app/push", %{endpoint: "http://127.0.0.1/up"})
    assert json_response(conn, 422) == %{"error" => "invalid_endpoint"}
    assert Push.endpoints(session.id) == []
  end

  test "DELETE /api/app/push removes the endpoint", %{conn: conn, session: session} do
    conn = put(conn, ~p"/api/app/push", %{endpoint: @endpoint_url})
    conn = delete(recycle_with_auth(conn), ~p"/api/app/push")
    assert response(conn, 204)
    assert Push.endpoints(session.id) == []
  end

  test "requires authentication" do
    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put(~p"/api/app/push", %{endpoint: @endpoint_url})

    assert json_response(conn, 401)
  end

  defp recycle_with_auth(conn) do
    [authorization] = get_req_header(conn, "authorization")
    conn |> recycle() |> put_req_header("authorization", authorization)
  end
end
