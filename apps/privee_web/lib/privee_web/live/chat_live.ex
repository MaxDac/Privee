defmodule PriveeWeb.ChatLive do
  @moduledoc """
  The chat screen. This is the only screen that the user will be able to see.
  """

  use PriveeWeb, :live_view

  alias Privee.Sessions.Message

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, messages: [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1>Chat</h1>
      <ul>
        <%= for message <- @messages do %>
          <li><%= message.text %></li>
        <% end %>
      </ul>
    </div>
    """
  end
end
