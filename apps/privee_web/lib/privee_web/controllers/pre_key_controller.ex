defmodule PriveeWeb.PreKeyController do
  use PriveeWeb, :controller

  require Logger

  def register(conn, %{"session_id" => session_id_str} = params) do
    session_id = String.to_integer(session_id_str)

    bundle = %{
      "identity_key" => params["identity_key"],
      "registration_id" => params["registration_id"],
      "signed_prekey" => %{
        "key_id" => params["signed_prekey"]["key_id"],
        "public_key" => params["signed_prekey"]["public_key"],
        "signature" => params["signed_prekey"]["signature"]
      },
      "one_time_prekeys" =>
        Enum.map(params["one_time_prekeys"] || [], fn pk ->
          %{"key_id" => pk["key_id"], "public_key" => pk["public_key"]}
        end)
    }

    Logger.debug("Registering prekey bundle via API for session #{session_id}")
    Privee.PreKeyStore.register_bundle(session_id, bundle)
    PriveeWeb.Endpoint.broadcast("prekeys:#{session_id}", "prekeys_available", %{})

    json(conn, %{status: "ok"})
  end
end
