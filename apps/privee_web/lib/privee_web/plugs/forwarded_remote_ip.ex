defmodule PriveeWeb.Plugs.ForwardedRemoteIp do
  @moduledoc """
  Sets `conn.remote_ip` to the client address reported by trusted reverse
  proxies, so per-client rate limits work behind Caddy, nginx or Fly.io.

  Configured with `config :privee_web, :proxy_hops, n` (`PROXY_HOPS` at
  runtime): the number of trusted proxies in front of the app. The client is
  the `n`-th address from the right of `X-Forwarded-For`, because each proxy
  appends the address it received the request from and anything further left
  is supplied by the client. With `0` (the default) the header is ignored.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:privee_web, :proxy_hops, 0) do
      hops when is_integer(hops) and hops > 0 -> put_forwarded_ip(conn, hops)
      _ -> conn
    end
  end

  defp put_forwarded_ip(conn, hops) do
    addresses =
      conn
      |> Plug.Conn.get_req_header("x-forwarded-for")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)

    with address when is_binary(address) <- Enum.at(addresses, -hops),
         {:ok, ip} <- :inet.parse_strict_address(String.to_charlist(address)) do
      %{conn | remote_ip: ip}
    else
      _ -> conn
    end
  end
end
