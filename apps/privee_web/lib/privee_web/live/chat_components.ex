defmodule PriveeWeb.ChatComponents do
  @moduledoc """
  A collection of functional components for the chat LiveView
  """

  use PriveeWeb, :html

  @doc """
  The chat input, where it will be possible to send text.
  """
  def chat_input(assigns) do
    ~H"""
    <div>
      <.input field={@form[:text]} placeholder="Write your message here" required />
    </div>
    """
  end

  @doc """
  A single chat entry in the chat screen.
  """
  def chat_entry(assigns) do
    ~H"""
    <div class={[
      "p-2",
      if @message.from == @current_session.id do
        "flex justify-end"
      else
        nil
      end
    ]}>
      <div class={[
        "flex flex-col w-full max-w-[500px] leading-1.5 p-4 border-gray-200 rounded-e-xl rounded-es-xl",
        if @message.from == @current_session.id do
          "bg-green-100 dark:bg-green-800"
        else
          "bg-gray-100 dark:bg-gray-700"
        end
      ]}>
        <p class="text-sm font-normal py-2.5 text-gray-900 dark:text-white">
          <%= @message.text %>
        </p>
      </div>
    </div>
    """
  end

  @doc """
  The chat screen, containing all the chat entries.
  """
  def chat_screen(assigns) do
    ~H"""
    <div :for={message <- @messages}>
      <.chat_entry 
        message={message}
        current_session={@current_session}
        selected_session={@selected_session}
      />
    </div>
    """
  end
end
