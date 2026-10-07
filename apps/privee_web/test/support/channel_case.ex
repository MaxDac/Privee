defmodule PriveeWeb.ChannelCase do
  @moduledoc """
  Test case for the channels of the native app socket.
  """

  use ExUnit.CaseTemplate

  alias Phoenix.ChannelTest
  alias Privee.Sessions
  alias PriveeWeb.App.AppAuth
  alias PriveeWeb.App.AppSocket

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
    token = Sessions.generate_session_token(session)

    {:ok, socket} =
      ChannelTest.__connect__(
        PriveeWeb.Endpoint,
        AppSocket,
        %{},
        connect_info: %{auth_token: AppAuth.encode_token(token)}
      )

    socket
  end
end
