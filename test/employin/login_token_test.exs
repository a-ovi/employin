defmodule Employin.LoginTokenTest do
  use ExUnit.Case, async: true

  alias Employin.LoginToken

  describe "generate_otp/0" do
    test "always returns 6 digits" do
      for _ <- 1..1_000 do
        assert LoginToken.generate_otp() =~ ~r/^\d{6}$/
      end
    end
  end

  describe "OTP tokens" do
    test "verify only with the matching code" do
      %{token: token, otp: otp} = LoginToken.create_otp_and_token("a@example.com")

      assert LoginToken.verify_otp(token, otp) == {:ok, "a@example.com"}
      assert LoginToken.verify_otp(token, " #{otp} ") == {:ok, "a@example.com"}
      assert {:error, :invalid} = LoginToken.verify_otp(token, wrong_otp(otp))
    end

    test "reject malformed input" do
      assert {:error, :invalid} = LoginToken.verify_otp(nil, "123456")
      assert {:error, :invalid} = LoginToken.verify_otp("garbage", "123456")
      assert {:error, :invalid} = LoginToken.verify_otp("garbage", nil)
    end
  end

  describe "purposes" do
    test "a token is only valid for the purpose it was issued for" do
      token = LoginToken.sign(:registration, "a@example.com")

      assert LoginToken.verify(:registration, token) == {:ok, "a@example.com"}
      assert {:error, :invalid} = LoginToken.verify(:session, token)
      assert {:error, :invalid} = LoginToken.verify(:otp, token)
    end

    test "session tokens expire after a minute" do
      config = Application.fetch_env!(:employin, LoginToken)
      salt = "#{config[:salt]} session login"
      signed_at = System.system_time(:second) - 61
      token = Phoenix.Token.sign(config[:secret], salt, "user-id", signed_at: signed_at)

      assert {:error, :expired} = LoginToken.verify(:session, token)
    end
  end

  defp wrong_otp(otp) do
    otp |> String.to_integer() |> Kernel.+(1) |> rem(1_000_000) |> Integer.to_string()
  end
end
