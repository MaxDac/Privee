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
    * `:req_options` - extra `Req` options (used by the tests)
  """

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
      for endpoint <- endpoints(session_id) do
        Task.Supervisor.start_child(Privee.TaskSupervisor, fn -> deliver(endpoint) end)
      end
    end

    :ok
  end

  @doc false
  def deliver(endpoint) do
    options =
      [
        body: @body,
        headers: [
          {"content-type", "text/plain"},
          {"ttl", "86400"},
          {"urgency", "high"}
        ],
        retry: false,
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
    insecure? = config()[:allow_insecure] == true

    case URI.new(endpoint) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" ->
        if insecure? or public_host?(host), do: :ok, else: {:error, :invalid_endpoint}

      {:ok, %URI{scheme: "http", host: host}} when is_binary(host) and host != "" and insecure? ->
        :ok

      _ ->
        {:error, :invalid_endpoint}
    end
  end

  def validate_endpoint(_endpoint), do: {:error, :invalid_endpoint}

  defp public_host?(host) do
    host = String.downcase(host)

    cond do
      host == "localhost" or String.ends_with?(host, ".localhost") -> false
      String.starts_with?(host, "[") -> false
      match?({:ok, _}, :inet.parse_address(String.to_charlist(host))) -> false
      not String.contains?(host, ".") -> false
      true -> true
    end
  end

  defp get_session_token(token) when is_binary(token) do
    token |> SessionToken.by_token_and_context_query("session") |> Repo.one()
  end

  defp get_session_token(_token), do: nil

  defp config, do: Application.get_env(:privee, __MODULE__, [])
end
