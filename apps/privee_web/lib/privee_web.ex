defmodule PriveeWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use PriveeWeb, :controller
      use PriveeWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: PriveeWeb.Layouts]

      import Plug.Conn
      import PriveeWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {PriveeWeb.Layouts, :app}

      unquote(html_helpers())
      unquote(js_flash_helpers())
    end
  end

  def chat_live_view do
    quote do
      use Phoenix.LiveView,
        layout: {PriveeWeb.Layouts, :chat_layout}

      unquote(html_helpers())
      unquote(js_flash_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import PriveeWeb.CoreComponents
      import PriveeWeb.Gettext

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())

      @doc """
      Assign a default action to the changeset. This function is useful when the form
      that uses the changeset does not have an action, so from the documentation it does not
      show the error.

      Please check [here](https://stackoverflow.com/a/43453618/8620481) for more information.
      """
      @spec assign_changeset_action(changeset :: Ecto.Changeset.t(), action :: atom()) ::
              Ecto.Changeset.t()
      def assign_changeset_action(changeset, action \\ :insert)
      def assign_changeset_action(%{valid?: true} = changeset, _), do: changeset
      def assign_changeset_action(changeset, action), do: %{changeset | action: action}
    end
  end

  defp js_flash_helpers do
    quote do
      @doc """
      Handles JavaScript-triggered flash messages.

      This function is automatically included in all LiveViews to handle
      flash messages sent from client-side JavaScript using the existing
      server-side flash system.
      """
      def handle_event("js_flash", %{"kind" => kind, "message" => message} = params, socket) do
        flash_title = Map.get(params, "title")
        kind_atom = String.to_existing_atom(kind)

        final_message = if flash_title do
          "#{flash_title} #{message}"
        else
          message
        end

        {:noreply, put_flash(socket, kind_atom, final_message)}
      rescue
        ArgumentError ->
          # Invalid kind provided, default to info
          flash_title = Map.get(params, "title")
          final_message = if flash_title do
            "#{flash_title} #{message}"
          else
            message
          end
          {:noreply, put_flash(socket, :info, final_message)}
      end
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: PriveeWeb.Endpoint,
        router: PriveeWeb.Router,
        statics: PriveeWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
