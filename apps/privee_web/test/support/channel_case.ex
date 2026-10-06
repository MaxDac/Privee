defmodule PriveeWeb.ChannelCase do
  @moduledoc """
  Test case for the channels of the native app socket.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import PriveeWeb.ChannelCase

      @endpoint PriveeWeb.Endpoint
    end
  end

  setup tags do
    Privee.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc "Returns an app socket authenticated as `session`."
  def app_socket(session) do
    token = Privee.Sessions.generate_session_token(session)

    {:ok, socket} =
      Phoenix.ChannelTest.__connect__(
        PriveeWeb.Endpoint,
        PriveeWeb.App.AppSocket,
        %{},
        connect_info: %{auth_token: PriveeWeb.App.AppAuth.encode_token(token)}
      )

    socket
  end
end
