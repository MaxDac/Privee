defmodule Privee.Push do
  @moduledoc """
  Content-free [UnifiedPush](https://unifiedpush.org) notifications for the
  native app.

  The app registers the endpoint given by its push distributor. When a message
  is stored for a session, every endpoint of that session receives a POST whose
  body is a constant: the app wakes up and fetches the encrypted messages
  through its socket. Pushes are rate-limited per recipient, and endpoints that
  the push server reports as gone (`404`, `410`) are removed.

  Configuration (`config :privee, Privee.Push`):

    * `:allow_insecure` - accept `http` and local endpoints (development only)
    * `:resolve_hosts` - check, before each delivery, that the endpoint host
      resolves only to public addresses (default `true`; disabled in tests)
    * `:req_options` - extra `Req` options (used by the tests)
  """

  import Bitwise
  import Ecto.Query

  alias Privee.Push.PushEndpoint
  alias Privee.RateLimiter
  alias Privee.Repo
  alias Privee.Sessions.SessionToken

  require Logger

  @max_endpoint_length 2048
  @pushes_per_window 1
  @push_window_ms 2_000
  @body "1"

  @doc """
  Registers (or replaces) the push endpoint of the app logged in with the raw
  session `token`.
  """
  @spec register_endpoint(binary(), term()) :: :ok | {:error, :invalid_endpoint | :not_found}
  def register_endpoint(token, endpoint) do
    with :ok <- validate_endpoint(endpoint),
         %SessionToken{} = session_token <- get_session_token(token) do
      Repo.transaction(fn ->
        PushEndpoint
        |> where([p], p.endpoint == ^endpoint or p.session_token_id == ^session_token.id)
        |> Repo.delete_all()

        Repo.insert!(%PushEndpoint{
          session_id: session_token.session_id,
          session_token_id: session_token.id,
          endpoint: endpoint
        })
      end)

      :ok
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Removes the push endpoint of the app logged in with the raw session `token`."
  @spec unregister_endpoint(binary()) :: :ok
  def unregister_endpoint(token) do
    PushEndpoint
    |> join(:inner, [p], t in assoc(p, :session_token))
    |> where([_p, t], t.token == ^token and t.context == "session")
    |> Repo.delete_all()

    :ok
  end

  @doc "Returns the push endpoints of `session_id`."
  @spec endpoints(non_neg_integer()) :: [String.t()]
  def endpoints(session_id) do
    PushEndpoint
    |> where([p], p.session_id == ^session_id)
    |> select([p], p.endpoint)
    |> Repo.all()
  end

  @doc """
  Notifies the apps of `session_id` that a message arrived. Deliveries are
  asynchronous; at most one notification per recipient is sent every
  #{@push_window_ms} milliseconds, which is enough since a single wake up
  fetches every pending message.
  """
  @spec notify(non_neg_integer()) :: :ok
  def notify(session_id) do
    with :ok <- RateLimiter.hit({:push, session_id}, @pushes_per_window, @push_window_ms) do
      session_id |> endpoints() |> Enum.each(&deliver_async/1)
    end

    :ok
  end

  defp deliver_async(endpoint) do
    Task.Supervisor.start_child(Privee.TaskSupervisor, fn -> deliver(endpoint) end)
  end

  @doc false
  def deliver(endpoint) do
    if public_destination?(endpoint) do
      post(endpoint)
    else
      Logger.info("Push delivery skipped: the endpoint does not resolve to public addresses")
      :error
    end
  end

  defp post(endpoint) do
    options =
      [
        body: @body,
        headers: [
          {"content-type", "text/plain"},
          {"ttl", "86400"},
          {"urgency", "high"}
        ],
        retry: false,
        redirect: false,
        connect_options: [timeout: 5_000],
        receive_timeout: 5_000
      ]
      |> Keyword.merge(config()[:req_options] || [])

    case Req.post(endpoint, options) do
      {:ok, %Req.Response{status: status}} when status in [404, 410] ->
        PushEndpoint |> where([p], p.endpoint == ^endpoint) |> Repo.delete_all()
        :gone

      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.info("Push delivery failed with status #{status}")
        :error

      {:error, exception} ->
        Logger.info("Push delivery failed: #{Exception.message(exception)}")
        :error
    end
  end

  @doc """
  Validates a push endpoint: an `https` URL with a host name, which is not a
  literal IP address or `localhost`, so the server cannot be pointed at internal
  services by address.
  """
  @spec validate_endpoint(term()) :: :ok | {:error, :invalid_endpoint}
  def validate_endpoint(endpoint)
      when is_binary(endpoint) and byte_size(endpoint) <= @max_endpoint_length do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: scheme, host: host}} when is_binary(host) and host != "" ->
        validate_host(scheme, host)

      _ ->
        {:error, :invalid_endpoint}
    end
  end

  def validate_endpoint(_endpoint), do: {:error, :invalid_endpoint}

  defp validate_host(scheme, host) do
    insecure? = config()[:allow_insecure] == true

    allowed? =
      (scheme == "https" and (insecure? or public_host?(host))) or
        (scheme == "http" and insecure?)

    if allowed?, do: :ok, else: {:error, :invalid_endpoint}
  end

  defp public_host?(host) do
    host = String.downcase(host)
    String.contains?(host, ".") and not local_host?(host) and not ip_literal?(host)
  end

  defp local_host?(host), do: host == "localhost" or String.ends_with?(host, ".localhost")

  defp ip_literal?(host) do
    String.starts_with?(host, "[") or
      match?({:ok, _}, :inet.parse_address(String.to_charlist(host)))
  end

  # Host names can resolve to internal addresses: every address must be public
  # right before delivering. Skipped with `:allow_insecure` and when
  # `:resolve_hosts` is false (tests).
  defp public_destination?(endpoint) do
    config = config()

    if config[:allow_insecure] == true or config[:resolve_hosts] == false do
      true
    else
      case resolve(URI.parse(endpoint).host) do
        [] -> false
        addresses -> Enum.all?(addresses, &public_address?/1)
      end
    end
  end

  defp resolve(host) when is_binary(host) do
    host = String.to_charlist(host)

    for family <- [:inet, :inet6],
        {:ok, addresses} <- [:inet.getaddrs(host, family)],
        address <- addresses,
        do: address
  end

  defp resolve(_host), do: []

  @non_public_ipv4 for {{a, b, c, d}, bits} <- [
                         {{0, 0, 0, 0}, 8},
                         {{10, 0, 0, 0}, 8},
                         {{100, 64, 0, 0}, 10},
                         {{127, 0, 0, 0}, 8},
                         {{169, 254, 0, 0}, 16},
                         {{172, 16, 0, 0}, 12},
                         {{192, 0, 0, 0}, 16},
                         {{192, 168, 0, 0}, 16},
                         {{198, 18, 0, 0}, 15},
                         {{224, 0, 0, 0}, 3}
                       ],
                       do: {a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d, bits}

  @doc """
  Whether `address` is a publicly routable IPv4 or IPv6 address, i.e. not
  loopback, private, link-local, shared, multicast, reserved or unspecified.
  """
  @spec public_address?(:inet.ip_address()) :: boolean()
  def public_address?({a, b, c, d}) do
    ip = a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d

    not Enum.any?(@non_public_ipv4, fn {network, bits} ->
      ip >>> (32 - bits) == network >>> (32 - bits)
    end)
  end

  def public_address?({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    public_address?({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})
  end

  def public_address?({first, second, _, _, _, _, _, _}) do
    not (first == 0 or first == 0x64 or
           first in 0xFC00..0xFDFF or
           first in 0xFE80..0xFEBF or
           first >= 0xFF00 or
           (first == 0x2001 and second == 0xDB8))
  end

  defp get_session_token(token) when is_binary(token) do
    token |> SessionToken.by_token_and_context_query("session") |> Repo.one()
  end

  defp get_session_token(_token), do: nil

  defp config, do: Application.get_env(:privee, __MODULE__, [])
end
