defmodule PriveeWeb.Instance do
  @moduledoc """
  Describes this Privee deployment to clients and users.

  Configured with `config :privee_web, :instance, name: ..., source_url: ...`
  (in production from the `PRIVEE_INSTANCE_NAME` and `PRIVEE_SOURCE_URL`
  environment variables, see `config/runtime.exs`).

  `source_url/0` must point to the source code actually running on this
  instance: the AGPL-3.0 requires offering it to every user interacting with
  the service over a network, so forks must set it to their own repository.
  """

  @api_version 1
  @default_source_url "https://github.com/MaxDac/Privee"

  @doc "Version of the native app API (`/api/app`, `/app/socket`) served by this instance."
  @spec api_version() :: pos_integer()
  def api_version, do: @api_version

  @doc "Optional human readable name of this instance."
  @spec name() :: String.t() | nil
  def name, do: config(:name)

  @doc "Where users can obtain the source code of this instance."
  @spec source_url() :: String.t()
  def source_url, do: config(:source_url) || @default_source_url

  @doc "Release version of the running server."
  @spec version() :: String.t()
  def version, do: :privee_web |> Application.spec(:vsn) |> to_string()

  @doc "The public description returned by `GET /api/app/info`."
  @spec info() :: map()
  def info do
    %{
      service: "privee",
      api_version: api_version(),
      version: version(),
      name: name(),
      source_url: source_url()
    }
  end

  defp config(key),
    do: :privee_web |> Application.get_env(:instance, []) |> Keyword.get(key) |> blank_to_nil()

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
