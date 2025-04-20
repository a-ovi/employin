defmodule EmployinWeb.UserAuth do
  use EmployinWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  def fetch_current_user(conn, _opts) do
    if user_id = get_session(conn, :user_id) do
      user = Employin.Users.get(user_id)
      assign(conn, :current_user, user)
    else
      assign(conn, :current_user, nil)
    end
  end

  def ensure_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def ensure_not_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> put_flash(:error, "You are already logged in.")
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

end
