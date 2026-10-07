defmodule PriveeWeb.Router do
  use PriveeWeb, :router

  import PriveeWeb.SessionAuth
  import PriveeWeb.App.AppAuth, only: [require_app_session: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PriveeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :app_session do
    plug :require_app_session
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:privee_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PriveeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PriveeWeb do
    pipe_through [:browser, :redirect_if_session_is_authenticated]

    live_session :redirect_if_session_is_authenticated,
      on_mount: [
        {PriveeWeb.SessionAuth, :redirect_if_session_is_authenticated},
        {PriveeWeb.Navigation, :home}
      ] do
      live "/", SessionRegistrationLive, :new
      live "/login", SessionLoginLive, :new
    end

    post "/sessions/log_in", SessionController, :create
  end

  scope "/", PriveeWeb do
    pipe_through [:browser, :require_authenticated_session]

    live_session :require_authenticated_session,
      on_mount: [
        {PriveeWeb.SessionAuth, :ensure_authenticated},
        {PriveeWeb.Navigation, :logged},
        PriveeWeb.SignalKeysLive
      ] do
      live "/privee", PriveeSelectorLive
      live "/chat/:session", Chat.ChatLive
    end
  end

  scope "/", PriveeWeb do
    pipe_through [:browser]

    get "/share/:session_name", SessionShareController, :share
    delete "/sessions/log_out", SessionController, :delete
  end

  ## Native app API

  scope "/api/app", PriveeWeb.App do
    pipe_through :api

    post "/sessions", SessionController, :register
    post "/sessions/log_in", SessionController, :log_in
  end

  scope "/api/app", PriveeWeb.App do
    pipe_through [:api, :app_session]

    get "/session", SessionController, :show
    delete "/session", SessionController, :delete
    put "/push", PushController, :update
    delete "/push", PushController, :delete
  end
end
