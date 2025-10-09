defmodule BautaWeb.Router do
  use BautaWeb, :router

  import BautaWeb.SessionAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BautaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", BautaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bauta_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BautaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", BautaWeb do
    pipe_through [:browser, :redirect_if_session_is_authenticated]

    live_session :redirect_if_session_is_authenticated,
      on_mount: [
        {BautaWeb.SessionAuth, :redirect_if_session_is_authenticated},
        {BautaWeb.Navigation, :home}
      ] do
      live "/", SessionRegistrationLive, :new
      live "/login", SessionLoginLive, :new
    end

    post "/sessions/log_in", SessionController, :create
  end

  scope "/", BautaWeb do
    pipe_through [:browser, :require_authenticated_session]

    live_session :require_authenticated_session,
      on_mount: [
        {BautaWeb.SessionAuth, :ensure_authenticated},
        {BautaWeb.Navigation, :logged}
      ] do
      live "/bauta", BautaSelectorLive
      live "/chat/:session", Chat.ChatLive
    end
  end

  scope "/", BautaWeb do
    pipe_through [:browser]

    get "/share/:session_name", SessionShareController, :share
    delete "/sessions/log_out", SessionController, :delete
  end
end
