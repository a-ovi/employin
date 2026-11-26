defmodule Employin.AuthTest do
  use Employin.DataCase, async: true

  alias Employin.Auth
  alias Employin.LoginToken

  describe "request_code/1" do
    test "limits login codes per email address" do
      email = unique_email()

      for _ <- 1..5, do: assert({:ok, %{otp: _, token: _}} = Auth.request_code(email))

      assert {:error, {:rate_limited, retry_after}} = Auth.request_code(String.upcase(email))
      assert retry_after > 0
      assert {:ok, _} = Auth.request_code(unique_email())
    end
  end

  describe "verify_code/2" do
    test "limits guesses per token, even for the right code afterwards" do
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(unique_email())

      for _ <- 1..5, do: assert({:error, :invalid} = Auth.verify_code(token, "000000x"))

      assert {:error, {:rate_limited, _}} = Auth.verify_code(token, otp)
    end

    test "does not consume the token" do
      email = unique_email()
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(email)

      assert {:ok, ^email} = Auth.verify_code(token, otp)
      assert {:ok, ^email} = Auth.verify_code(token, otp)
    end
  end

  describe "single use" do
    test "a login code can be consumed once" do
      email = unique_email()
      %{token: token, otp: otp} = LoginToken.create_otp_and_token(email)

      assert {:ok, ^email} = Auth.consume_code(token, otp)
      assert {:error, :used} = Auth.consume_code(token, otp)
    end

    test "a session token can be consumed once" do
      token = LoginToken.sign(:session, "some-user-id")

      assert {:ok, "some-user-id"} = Auth.consume_session_token(token)
      assert {:error, :used} = Auth.consume_session_token(token)
    end
  end
end
