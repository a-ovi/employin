defmodule EmployinWeb.Router do
  use EmployinWeb, :router

  import EmployinWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmployinWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  scope "/", EmployinWeb do
    pipe_through [:browser, :ensure_not_authenticated]

    live_session :guest, on_mount: [{EmployinWeb.UserAuth, :redirect_if_authenticated}] do
      live "/login", LoginLive
      live "/profile/setup", RegistrationLive
    end

    # The magic link (GET) and the OTP form (POST) share one endpoint.
    get "/login/verify", SessionController, :otp_check
    post "/login/verify", SessionController, :otp_check
    post "/login/with_token", SessionController, :login
  end

  scope "/", EmployinWeb do
    pipe_through [:browser, :ensure_authenticated]

    live_session :authenticated, on_mount: [{EmployinWeb.UserAuth, :ensure_authenticated}] do
      live "/", HomeLive
    end

    delete "/logout", SessionController, :logout
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:employin, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EmployinWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
