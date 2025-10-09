defmodule BautaWeb.Navigation do
  @moduledoc """
  Handles the common navigation logic for LiveViews.
  """

  use BautaWeb, :verified_routes

  @doc """
  Assign the navigation constant to the live view based on its placement.
  """
  def on_mount(:home, _params, _session, socket) do
    {:cont, Phoenix.Component.assign(socket, :navigate_to, ~p"/")}
  end

  def on_mount(:logged, _params, _session, socket) do
    {:cont, Phoenix.Component.assign(socket, :navigate_to, ~p"/bauta")}
  end
end
