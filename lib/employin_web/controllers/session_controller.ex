defmodule EmployinWeb.SessionController do
  use EmployinWeb, :controller

  alias Employin.LoginToken
  alias Employin.Users

  @login_token_max_age 30

  def otp_check(conn, %{"token" => token, "otp" => otp}) do
    case LoginToken.verify_token_with_otp(token, otp) do
      {:ok, email} ->
        login_or_create_user(conn, email)
      {:error, _} ->
        conn
        |> put_status(401)
        |> put_view(EmployinWeb.ErrorHTML)
        |> put_root_layout(html: {EmployinWeb.ErrorHTML, :root})
        |> assign(:title, "Invalid or Expired Link")
        |> assign(:error_msg, "The link you're trying to access is no longer valid or has expired.")
        |> render("401.html")
    end
  end

  def login(conn, %{"token" => token}) do
    case LoginToken.verify(token, max_age: @login_token_max_age) do
      {:ok, user_id} ->
        login_user(conn, user_id)
      {:error, _} ->
        conn
        |> put_status(401)
        |> put_view(EmployinWeb.ErrorHTML)
        |> put_root_layout(html: {EmployinWeb.ErrorHTML, :root})
        |> assign(:title, "Login Token Invalid or Expired")
        |> assign(:error_msg, "Your login token is invalid or has expired. Please login again.")
        |> render("401.html")
    end
  end

  def logout(conn, _params) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      EmployinWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> put_flash(:info, "Logged out Successfully")
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  # def otp_submit(conn, %{"token" => token, "otp" => otp}) do
  #   case LoginToken.verify_token_with_otp(token, otp) do
  #     {:ok, email} ->
  #       conn
  #       |> redirect(to: ~p"/")

  #     {:error, _} ->
  #       conn
  #       |> put_session(:token, token)
  #       |> redirect(to: ~p"/login?token=#{token}")
  #   end
  # end

  defp login_or_create_user(conn, email) do
    case Users.get_by_email(email) do
      nil ->
        complete_registration(conn, email)
      user ->
        login_user(conn, user.id)
    end
  end


  defp login_user(conn, user_id) do
    conn
    |> renew_session()
    |> put_session(:user_id, user_id)
    |> put_session(:live_socket_id, "users_socket:#{user_id}")
    |> put_flash(:info, "Welcome Back!")
    |> redirect(to: ~p"/")
  end

  defp complete_registration(conn, email) do
    token = LoginToken.sign(email)
    redirect(conn, to: ~p"/profile/setup?token=#{token}")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

end
