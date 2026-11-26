defmodule EmployinWeb.UserAuth do
  @moduledoc """
  Authentication plugs (for controllers) and `on_mount` hooks (for LiveViews).

  The session stores only the user's id under `"user_id"`. Both the plugs and the
  hooks resolve it to `:current_user`, so a deleted user is logged out on their
  next request or LiveView mount.
  """
  use EmployinWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Employin.Users

  ## Plugs

  def fetch_current_user(conn, _opts) do
    user = conn |> get_session(:user_id) |> get_user()
    assign(conn, :current_user, user)
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

  ## LiveView hooks

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must be logged in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn -> get_user(session["user_id"]) end)
  end

  defp get_user(nil), do: nil
  defp get_user(user_id), do: Users.get(user_id)
end
