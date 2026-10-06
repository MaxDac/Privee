defmodule PriveeWeb.App.SessionControllerTest do
  use PriveeWeb.ConnCase, async: true

  import Privee.SessionsFixtures

  alias Privee.Sessions
  alias PriveeWeb.App.AppAuth

  # Each test gets its own client address, so the per-IP rate limit is not shared.
  setup %{conn: conn} do
    ip = {10, :rand.uniform(255), :rand.uniform(255), :rand.uniform(255)}
    %{conn: conn |> Map.put(:remote_ip, ip) |> put_req_header("accept", "application/json")}
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "POST /api/app/sessions" do
    test "registers a session with a recovery phrase and logs in", %{conn: conn} do
      conn =
        post(conn, ~p"/api/app/sessions", %{"recovery_phrase" => session_recovery_phrase()})

      assert %{"token" => token, "session" => %{"session_name" => name, "is_quick" => false}} =
               json_response(conn, 201)

      assert {:ok, session, _raw} = AppAuth.authenticate(token)
      assert session.session_name == name
      assert session.has_logged
    end

    test "registers a quick session, which cannot be logged into again", %{conn: conn} do
      conn = post(conn, ~p"/api/app/sessions", %{"is_quick" => true})

      assert %{"session" => %{"session_name" => name, "is_quick" => true}} =
               json_response(conn, 201)

      conn =
        post(recycle(conn), ~p"/api/app/sessions/log_in", %{session_name: name, is_quick: true})

      assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
    end

    test "uses the requested session name", %{conn: conn} do
      name = generate_new_unique_session_name()

      conn =
        post(conn, ~p"/api/app/sessions", %{
          "session_name" => name,
          "recovery_phrase" => session_recovery_phrase()
        })

      assert %{"session" => %{"session_name" => ^name}} = json_response(conn, 201)
    end

    test "rejects invalid attributes", %{conn: conn} do
      conn = post(conn, ~p"/api/app/sessions", %{"recovery_phrase" => "short"})

      assert %{"error" => "invalid", "errors" => %{"recovery_phrase" => [_ | _]}} =
               json_response(conn, 422)
    end
  end

  describe "POST /api/app/sessions/log_in" do
    test "logs in with the recovery phrase", %{conn: conn} do
      session = session_fixture()

      conn =
        post(conn, ~p"/api/app/sessions/log_in", %{
          session_name: session.session_name,
          recovery_phrase: session_recovery_phrase()
        })

      assert %{"token" => token} = json_response(conn, 200)
      assert {:ok, %{id: id}, _raw} = AppAuth.authenticate(token)
      assert id == session.id
    end

    test "logs into a quick session that was never logged into", %{conn: conn} do
      session = quick_session_fixture()

      conn =
        post(conn, ~p"/api/app/sessions/log_in", %{
          session_name: session.session_name,
          is_quick: "true"
        })

      assert %{"session" => %{"is_quick" => true}} = json_response(conn, 200)
    end

    test "rejects a wrong recovery phrase", %{conn: conn} do
      session = session_fixture()

      conn =
        post(conn, ~p"/api/app/sessions/log_in", %{
          session_name: session.session_name,
          recovery_phrase: "This is definitely not the phrase"
        })

      assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
    end

    test "does not log into a regular session as a quick one", %{conn: conn} do
      session = session_fixture()

      conn =
        post(conn, ~p"/api/app/sessions/log_in", %{
          session_name: session.session_name,
          is_quick: true
        })

      assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
    end

    test "rate limits the attempts of a client", %{conn: conn} do
      for _ <- 1..10 do
        conn = post(conn, ~p"/api/app/sessions/log_in", %{})
        assert json_response(conn, 401)
      end

      conn = post(conn, ~p"/api/app/sessions/log_in", %{})
      assert json_response(conn, 429) == %{"error" => "rate_limited"}
    end
  end

  describe "authenticated requests" do
    setup %{conn: conn} do
      session = session_fixture()
      token = session |> Sessions.generate_session_token() |> AppAuth.encode_token()
      %{conn: conn, session: session, token: token}
    end

    test "GET /api/app/session returns the session", %{conn: conn, session: session, token: token} do
      conn = conn |> bearer(token) |> get(~p"/api/app/session")

      assert json_response(conn, 200) == %{
               "session" => %{"session_name" => session.session_name, "is_quick" => false}
             }
    end

    test "requires a valid token", %{conn: conn} do
      assert conn |> get(~p"/api/app/session") |> json_response(401)
      assert conn |> bearer("not a token") |> get(~p"/api/app/session") |> json_response(401)

      unknown = AppAuth.encode_token(:crypto.strong_rand_bytes(32))
      assert conn |> bearer(unknown) |> get(~p"/api/app/session") |> json_response(401)
    end

    test "DELETE /api/app/session revokes the token and disconnects sockets", %{
      conn: conn,
      token: token
    } do
      {:ok, raw} = AppAuth.decode_token(token)
      PriveeWeb.Endpoint.subscribe(AppAuth.socket_id(raw))

      conn = conn |> bearer(token) |> delete(~p"/api/app/session")
      assert response(conn, 204)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

      assert recycle(conn) |> bearer(token) |> get(~p"/api/app/session") |> json_response(401)
    end
  end
end
