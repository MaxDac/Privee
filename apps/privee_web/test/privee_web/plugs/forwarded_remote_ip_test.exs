defmodule PriveeWeb.Plugs.ForwardedRemoteIpTest do
  use PriveeWeb.ConnCase, async: false

  alias PriveeWeb.Plugs.ForwardedRemoteIp

  setup do
    previous = Application.fetch_env(:privee_web, :proxy_hops)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:privee_web, :proxy_hops, value)
        :error -> Application.delete_env(:privee_web, :proxy_hops)
      end
    end)
  end

  defp remote_ip(hops, forwarded_for) do
    Application.put_env(:privee_web, :proxy_hops, hops)

    forwarded_for
    |> Enum.reduce(build_conn(), fn value, conn ->
      Plug.Conn.put_req_header(conn, "x-forwarded-for", value)
    end)
    |> ForwardedRemoteIp.call([])
    |> Map.fetch!(:remote_ip)
  end

  test "ignores the header without trusted proxies" do
    assert remote_ip(0, ["203.0.113.7"]) == {127, 0, 0, 1}
  end

  test "uses the address appended by the trusted proxy, not spoofed ones" do
    assert remote_ip(1, ["203.0.113.7"]) == {203, 0, 113, 7}
    assert remote_ip(1, ["10.0.0.1, 203.0.113.7"]) == {203, 0, 113, 7}
    assert remote_ip(1, ["2001:db8::1"]) == {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
  end

  test "counts hops from the right across proxies" do
    assert remote_ip(2, ["1.2.3.4, 203.0.113.7, 198.51.100.2"]) == {203, 0, 113, 7}
  end

  test "keeps the peer address for missing or invalid values" do
    assert remote_ip(1, []) == {127, 0, 0, 1}
    assert remote_ip(2, ["203.0.113.7"]) == {127, 0, 0, 1}
    assert remote_ip(1, ["203.0.113.7, not-an-ip"]) == {127, 0, 0, 1}
  end
end
