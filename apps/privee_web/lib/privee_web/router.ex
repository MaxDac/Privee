defmodule PriveeWeb.Router do
  use PriveeWeb, :router

  import PriveeWeb.SessionAuth

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

  # Other scopes may use custom stacks.
  # scope "/api", PriveeWeb do
  #   pipe_through :api
  # end

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
      on_mount: [{PriveeWeb.SessionAuth, :redirect_if_session_is_authenticated}] do
      live "/sessions/register", SessionRegistrationLive, :new
      live "/", SessionLoginLive, :new
    end

    post "/sessions/log_in", SessionController, :create
  end

  scope "/", PriveeWeb do
    pipe_through [:browser, :require_authenticated_session]

    live_session :require_authenticated_session,
      on_mount: [{PriveeWeb.SessionAuth, :ensure_authenticated}] do
      live "/chat", Chat.ChatLive
    end
  end

  scope "/", PriveeWeb do
    pipe_through [:browser]

    delete "/sessions/log_out", SessionController, :delete
  end
end
