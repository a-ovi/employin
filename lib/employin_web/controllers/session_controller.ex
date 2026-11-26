defmodule EmployinWeb.SessionController do
  @moduledoc """
  Turns verified login tokens into a cookie session.

    * `otp_check/2` – entry point of the magic link and of the OTP form. Logs
      existing users in, or sends new users to the profile setup page.
    * `login/2` – used right after registration with a short-lived `:session` token.
    * `logout/2` – drops the session and disconnects open LiveViews.
  """
  use EmployinWeb, :controller

  alias Employin.LoginToken
  alias Employin.Users

  def otp_check(conn, %{"token" => token, "otp" => otp}) do
    case LoginToken.verify_otp(token, otp) do
      {:ok, email} ->
        login_or_register(conn, email)

      {:error, _} ->
        unauthorized(
          conn,
          "Invalid or Expired Link",
          "The link you're trying to access is no longer valid or has expired."
        )
    end
  end

  def otp_check(conn, _params) do
    unauthorized(conn, "Invalid Link", "This login link is incomplete. Please request a new one.")
  end

  def login(conn, %{"token" => token}) do
    with {:ok, user_id} <- LoginToken.verify(:session, token),
         %{} = user <- Users.get(user_id) do
      login_user(conn, user.id, "Welcome to Employin!")
    else
      _ ->
        unauthorized(
          conn,
          "Login Token Invalid or Expired",
          "Your login token is invalid or has expired. Please login again."
        )
    end
  end

  def login(conn, _params), do: redirect(conn, to: ~p"/login")

  def logout(conn, _params) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      EmployinWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/login")
  end

  defp login_or_register(conn, email) do
    case Users.get_by_email(email) do
      nil -> redirect(conn, to: ~p"/profile/setup?token=#{LoginToken.sign(:registration, email)}")
      user -> login_user(conn, user.id)
    end
  end

  defp login_user(conn, user_id, message \\ "Welcome back!") do
    conn
    |> renew_session()
    |> put_session(:user_id, user_id)
    |> put_session(:live_socket_id, "users_socket:#{user_id}")
    |> put_flash(:info, message)
    |> redirect(to: ~p"/")
  end

  defp unauthorized(conn, title, message) do
    conn
    |> put_status(:unauthorized)
    |> put_view(EmployinWeb.ErrorHTML)
    |> put_root_layout(html: {EmployinWeb.ErrorHTML, :root})
    |> assign(:title, title)
    |> assign(:error_msg, message)
    |> render("401.html")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
