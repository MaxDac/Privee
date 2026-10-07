defmodule Privee.PushTest do
  use Privee.DataCase, async: true

  import Privee.SessionsFixtures

  alias Privee.Push
  alias Privee.Sessions

  @endpoint_url "https://push.example.com/up/abc"

  setup do
    session = session_fixture()
    token = Sessions.generate_session_token(session)
    %{session: session, token: token}
  end

  describe "validate_endpoint/1" do
    test "accepts public https URLs" do
      assert :ok = Push.validate_endpoint(@endpoint_url)
      assert :ok = Push.validate_endpoint("https://ntfy.sh/upAbC?up=1")
    end

    test "rejects non https, local, IP and oversized endpoints" do
      for endpoint <- [
            "http://push.example.com/up",
            "ftp://push.example.com/up",
            "https://localhost/up",
            "https://foo.localhost/up",
            "https://127.0.0.1/up",
            "https://10.0.2.2:8080/up",
            "https://[::1]/up",
            "https://intranet/up",
            "not a url",
            "https://push.example.com/" <> String.duplicate("a", 2048),
            nil,
            42
          ] do
        assert {:error, :invalid_endpoint} = Push.validate_endpoint(endpoint),
               "expected #{inspect(endpoint)} to be rejected"
      end
    end
  end

  describe "register_endpoint/2 and unregister_endpoint/1" do
    test "registers and replaces the endpoint of a token", %{session: session, token: token} do
      assert :ok = Push.register_endpoint(token, @endpoint_url)
      assert Push.endpoints(session.id) == [@endpoint_url]

      assert :ok = Push.register_endpoint(token, @endpoint_url <> "2")
      assert Push.endpoints(session.id) == [@endpoint_url <> "2"]
    end

    test "keeps an endpoint per logged in app", %{session: session, token: token} do
      other_token = Sessions.generate_session_token(session)

      :ok = Push.register_endpoint(token, @endpoint_url)
      :ok = Push.register_endpoint(other_token, @endpoint_url <> "2")

      assert Enum.sort(Push.endpoints(session.id)) == [@endpoint_url, @endpoint_url <> "2"]
    end

    test "moves an endpoint re-registered by another session", %{session: session, token: token} do
      other = session_fixture(%{session_name: generate_new_unique_session_name()})
      other_token = Sessions.generate_session_token(other)

      :ok = Push.register_endpoint(token, @endpoint_url)
      :ok = Push.register_endpoint(other_token, @endpoint_url)

      assert Push.endpoints(session.id) == []
      assert Push.endpoints(other.id) == [@endpoint_url]
    end

    test "rejects invalid endpoints and unknown tokens", %{token: token} do
      assert {:error, :invalid_endpoint} = Push.register_endpoint(token, "http://example.com")

      assert {:error, :not_found} =
               Push.register_endpoint(:crypto.strong_rand_bytes(32), @endpoint_url)
    end

    test "unregisters the endpoint", %{session: session, token: token} do
      :ok = Push.register_endpoint(token, @endpoint_url)
      assert :ok = Push.unregister_endpoint(token)
      assert Push.endpoints(session.id) == []
    end

    test "logging out removes the endpoint", %{session: session, token: token} do
      :ok = Push.register_endpoint(token, @endpoint_url)
      Sessions.delete_session_token(token)
      assert Push.endpoints(session.id) == []
    end
  end

  describe "notify/1" do
    test "posts a content-free notification to every endpoint", %{session: session, token: token} do
      :ok = Push.register_endpoint(token, @endpoint_url)
      test_pid = self()

      Req.Test.stub(Push, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:push, conn.host, conn.request_path, body})
        Plug.Conn.send_resp(conn, 201, "")
      end)

      assert :ok = Push.notify(session.id)
      assert_receive {:push, "push.example.com", "/up/abc", "1"}

      # Notifications within the debounce window are coalesced.
      assert :ok = Push.notify(session.id)
      refute_receive {:push, _, _, _}, 100
    end

    test "removes endpoints which are gone", %{session: session, token: token} do
      :ok = Push.register_endpoint(token, @endpoint_url)

      Req.Test.stub(Push, &Plug.Conn.send_resp(&1, 410, ""))

      assert Push.deliver(@endpoint_url) == :gone
      assert Push.endpoints(session.id) == []
    end

    test "keeps endpoints on transient failures", %{session: session, token: token} do
      :ok = Push.register_endpoint(token, @endpoint_url)

      Req.Test.stub(Push, &Plug.Conn.send_resp(&1, 503, ""))

      assert Push.deliver(@endpoint_url) == :error
      assert Push.endpoints(session.id) == [@endpoint_url]
    end
  end
end
