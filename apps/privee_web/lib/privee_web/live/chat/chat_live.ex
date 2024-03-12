defmodule PriveeWeb.Chat.ChatLive do
  @moduledoc """
  The live view for the chat.
  """

  use PriveeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>chat</div>
    """
  end
end
