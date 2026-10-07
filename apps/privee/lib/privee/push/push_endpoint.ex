defmodule Privee.Push.PushEndpoint do
  @moduledoc """
  A UnifiedPush endpoint registered by a logged in app. Bound to the session
  token it was registered with, so logging out removes it.
  """

  use Ecto.Schema

  schema "push_endpoints" do
    field :endpoint, :string, redact: true
    belongs_to :session, Privee.Sessions.Session
    belongs_to :session_token, Privee.Sessions.SessionToken

    timestamps(updated_at: false)
  end
end
