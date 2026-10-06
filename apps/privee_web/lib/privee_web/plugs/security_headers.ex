defmodule PriveeWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Plug to add security headers to HTTP responses.

  This plug implements security best practices recommended by Lighthouse:
  - Content-Security-Policy (CSP) to prevent XSS attacks
  - HTTP Strict Transport Security (HSTS) to enforce HTTPS
  - Cross-Origin-Opener-Policy (COOP) for origin isolation

  Note: Trusted Types directive is not included as it conflicts with Phoenix LiveView's
  innerHTML usage. This is a known limitation that will be addressed when LiveView
  adds support for Trusted Types in the future.
  """
  import Plug.Conn

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", csp_header())
    |> put_resp_header("strict-transport-security", hsts_header())
    |> put_resp_header("cross-origin-opener-policy", coop_header())
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "SAMEORIGIN")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
  end

  defp csp_header do
    # Note: require-trusted-types-for directive is intentionally omitted
    # Phoenix LiveView uses innerHTML for DOM updates, which requires TrustedHTML assignment.
    # Adding this directive causes: "Failed to set the 'innerHTML' property on 'Element':
    # This document requires 'TrustedHTML' assignment."
    # This can be re-enabled once LiveView adds Trusted Types support.
    """
    default-src 'self';
    script-src 'self' 'unsafe-inline' 'unsafe-eval';
    style-src 'self' 'unsafe-inline';
    img-src 'self' data: https:;
    font-src 'self' data:;
    connect-src 'self' wss: ws:;
    object-src 'none';
    base-uri 'self';
    form-action 'self';
    frame-ancestors 'self';
    """
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp hsts_header do
    # max-age=31536000 (1 year), includeSubDomains, and preload
    "max-age=31536000; includeSubDomains; preload"
  end

  defp coop_header do
    # same-origin provides the strongest isolation
    "same-origin"
  end
end
