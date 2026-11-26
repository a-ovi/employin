defmodule EmployinWeb.SessionControllerTest do
  use EmployinWeb.ConnCase, async: true

  alias Employin.LoginToken

  describe "otp_check (magic link / OTP form)" do
    test "logs in an existing user", %{conn: conn} do
      user = user_fixture()
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(user.email)

      conn = get(conn, ~p"/login/verify?token=#{token}&otp=#{otp}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_id) == user.id
    end

    test "sends new users to profile setup", %{conn: conn} do
      %{token: token, otp: otp} = LoginToken.create_otp_and_token("new@example.com")

      conn = post(conn, ~p"/login/verify", %{"token" => token, "otp" => otp})

      assert "/profile/setup?token=" <> registration_token = redirected_to(conn)

      assert {:ok, "new@example.com"} =
               LoginToken.verify(:registration, URI.decode_www_form(registration_token))

      refute get_session(conn, :user_id)
    end

    test "a login link works only once", %{conn: conn} do
      user = user_fixture()
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(user.email)
      link = ~p"/login/verify?token=#{token}&otp=#{otp}"

      assert redirected_to(get(conn, link)) == ~p"/"
      assert html_response(get(build_conn(), link), 401) =~ "Link Already Used"
    end

    test "stops accepting guesses for a token", %{conn: conn} do
      %{token: token, otp: otp} = LoginToken.create_otp_and_token("a@example.com")

      for _ <- 1..5, do: get(build_conn(), ~p"/login/verify?token=#{token}&otp=000000x")

      assert html_response(get(conn, ~p"/login/verify?token=#{token}&otp=#{otp}"), 401) =~
               "Too Many Attempts"
    end

    test "rejects a wrong code", %{conn: conn} do
      %{token: token} = LoginToken.create_otp_and_token("a@example.com")

      conn = get(conn, ~p"/login/verify?token=#{token}&otp=000000x")

      assert html_response(conn, 401) =~ "Invalid or Expired Link"
    end

    test "rejects incomplete links", %{conn: conn} do
      assert html_response(get(conn, ~p"/login/verify"), 401) =~ "Invalid Link"
    end
  end

  describe "login (after registration)" do
    test "accepts session tokens only", %{conn: conn} do
      user = user_fixture()

      bad =
        post(conn, ~p"/login/with_token", %{"token" => LoginToken.sign(:registration, user.id)})

      assert html_response(bad, 401) =~ "Login Token Invalid or Expired"

      conn = post(conn, ~p"/login/with_token", %{"token" => LoginToken.sign(:session, user.id)})
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_id) == user.id
    end
  end

  describe "logout" do
    setup :register_and_log_in_user

    test "clears the session", %{conn: conn} do
      conn = delete(conn, ~p"/logout")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_id)
    end
  end
end
