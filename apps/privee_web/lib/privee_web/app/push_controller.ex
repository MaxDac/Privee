defmodule PriveeWeb.App.PushController do
  @moduledoc """
  Registers the [UnifiedPush](https://unifiedpush.org) endpoint of the
  authenticated app, see `Privee.Push`.

    * `PUT /api/app/push` - `%{endpoint}`; replaces the app's endpoint.
    * `DELETE /api/app/push` - removes it.
  """

  use PriveeWeb, :controller

  alias Privee.Push

  def update(conn, params) do
    case Push.register_endpoint(conn.assigns.app_token, params["endpoint"]) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, :invalid_endpoint} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_endpoint"})

      {:error, :not_found} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
    end
  end

  def delete(conn, _params) do
    Push.unregister_endpoint(conn.assigns.app_token)
    send_resp(conn, :no_content, "")
  end
end
