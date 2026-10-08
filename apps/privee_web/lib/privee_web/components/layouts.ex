defmodule PriveeWeb.Layouts do
  use PriveeWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the default app layout, with the navigation header and a centered content area.

  ## Examples

      <Layouts.app flash={@flash} current_session={@current_session} navigate_to={@navigate_to}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_session, :any, default: nil, doc: "the currently authenticated session"
  attr :navigate_to, :string, default: "/", doc: "the logo link destination"
  attr :locale, :string, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.sticky_header>
      <.menu current_session={@current_session} navigate_to={@navigate_to} locale={@locale} />
    </.sticky_header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl">
        <.flash_group flash={@flash} locale={@locale} /> {render_slot(@inner_block)}
      </div>
    </main>
    """
  end

  @doc """
  Renders the full-width chat layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_session, :any, default: nil, doc: "the currently authenticated session"
  attr :navigate_to, :string, default: "/", doc: "the logo link destination"
  attr :locale, :string, required: true
  slot :inner_block, required: true

  def chat(assigns) do
    ~H"""
    <.sticky_header>
      <.menu current_session={@current_session} navigate_to={@navigate_to} locale={@locale} />
    </.sticky_header>
    <.flash_group flash={@flash} locale={@locale} /> {render_slot(@inner_block)}
    """
  end

  @doc """
  Shows the flash group with standard titles and content using DaisyUI alert styling.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"
  attr :locale, :string, default: "en"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-4 right-4 z-50 space-y-2">
      <.flash kind={:info} title={lgettext(@locale, "Success!")} flash={@flash} locale={@locale} />
      <.flash kind={:error} title={lgettext(@locale, "Error!")} flash={@flash} locale={@locale} />
      <.flash kind={:warning} title={lgettext(@locale, "Warning!")} flash={@flash} locale={@locale} />
      <.flash
        id="client-error"
        kind={:error}
        title={lgettext(@locale, "We can't find the internet")}
        locale={@locale}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {lgettext(@locale, "Attempting to reconnect")}
        <svg
          class="w-6 h-6 text-gray-800 dark:text-white"
          aria-hidden="true"
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          fill="none"
          viewBox="0 0 24 24"
        >
          <path
            stroke="currentColor"
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M17.651 7.65a7.131 7.131 0 0 0-12.68 3.15M18.001 4v4h-4m-7.652 8.35a7.13 7.13 0 0 0 12.68-3.15M6 20v-4h4"
          />
        </svg>
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={lgettext(@locale, "Something went wrong!")}
        locale={@locale}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {lgettext(@locale, "Hang in there while we get back on track")}
        <svg
          class="w-6 h-6 text-gray-800 dark:text-white"
          aria-hidden="true"
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          fill="none"
          viewBox="0 0 24 24"
        >
          <path
            stroke="currentColor"
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M17.651 7.65a7.131 7.131 0 0 0-12.68 3.15M18.001 4v4h-4m-7.652 8.35a7.13 7.13 0 0 0 12.68-3.15M6 20v-4h4"
          />
        </svg>
      </.flash>
    </div>
    """
  end
end
