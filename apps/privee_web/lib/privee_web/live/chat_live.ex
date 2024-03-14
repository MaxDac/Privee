defmodule PriveeWeb.ChatLive do
  @moduledoc """
  This component represents a privee, or a chat where two sessions can actually talk.
  """

  use PriveeWeb, :chat_live_view

  import PriveeWeb.ChatComponents

  alias Privee.Sessions
  alias Privee.Sessions.Message

  @impl true
  def mount(%{"session" => selected_session}, _session, socket) do
    {:ok,
     socket
     |> assign(:selected_session, selected_session)
     |> assign_form()}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> push_navigate(to: ~p"/privee")}
  end

  @impl true
  def handle_event("validate", %{"message" => _params}, socket) do
    {:noreply,
     socket
     |> assign_form()}
  end

  @impl true
  def handle_event("create", %{"message" => params}, socket) do
    {:noreply,
     socket
     |> assign_form(params)}
  end

  defp assign_form(socket, attrs \\ %{}) do
    form =
      Sessions.change_message(%Message{}, attrs)
      |> to_form()

    assign(socket, :form, form)
  end
end
