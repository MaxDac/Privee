defmodule PriveeWeb.ChatLive do
  @moduledoc """
  This component represents a privee, or a chat where two sessions can actually talk.
  """
  
  use PriveeWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      <%= @selected_session %>
    </.header>
    """
  end

  @impl true
  def mount(%{"session" => selected_session}, _session, socket) do
    {:ok, 
     socket
     |> assign(:selected_session, selected_session)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, 
     socket
     |> push_navigate(to: ~p"/privee")}
  end
end
