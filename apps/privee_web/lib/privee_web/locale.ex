defmodule PriveeWeb.Locale do
  @moduledoc "Browser-local language preference and native API language negotiation."

  import Plug.Conn

  @languages [
    {"English", "en"},
    {"Italiano", "it"},
    {"Português", "pt-PT"},
    {"Español", "es"},
    {"Français", "fr"}
  ]
  @tags Enum.map(@languages, &elem(&1, 1))
  @cookie "privee_locale"

  def languages, do: @languages
  def valid?(tag), do: tag in @tags
  def normalize(tag), do: if(valid?(tag), do: tag, else: "en")

  def put_locale(tag) do
    locale = normalize(tag)
    Gettext.put_locale(PriveeWeb.Gettext, locale)
    locale
  end

  def init(mode), do: mode

  def call(conn, :request) do
    conn = fetch_cookies(conn)
    locale = put_locale(conn.cookies[@cookie])

    assign(conn, :locale, locale)
  end

  def call(conn, :browser) do
    conn = call(conn, :request)
    put_session(conn, "locale", conn.assigns.locale)
  end

  def call(conn, :api) do
    locale = conn |> get_req_header("accept-language") |> Enum.join(",") |> negotiate()
    assign(conn, :locale, put_locale(locale))
  end

  def negotiate(header) do
    header
    |> String.split(",")
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      [tag | parameters] = String.split(String.trim(entry), ";")

      quality = Enum.find_value(parameters, 1.0, &quality_parameter/1)

      {match_tag(tag), quality, index}
    end)
    |> Enum.filter(fn {tag, q, _} -> tag != nil and q > 0 end)
    |> Enum.sort_by(fn {_, q, index} -> {-q, index} end)
    |> case do
      [{tag, _, _} | _] -> tag
      [] -> "en"
    end
  end

  defp quality_parameter(parameter) do
    case String.split(String.trim(parameter), "=", parts: 2) do
      ["q", value] -> parse_quality(value)
      _ -> nil
    end
  end

  defp parse_quality(value) do
    case Float.parse(value) do
      {q, ""} when q >= 0 and q <= 1 -> q
      _ -> 0.0
    end
  end

  defp match_tag(tag) do
    case tag |> String.downcase() |> String.split("-") |> hd() do
      "en" -> "en"
      "it" -> "it"
      "pt" -> "pt-PT"
      "es" -> "es"
      "fr" -> "fr"
      _ -> nil
    end
  end
end
