defmodule Employin.LoginToken do

  @default_otp_len 6
  @max_age 3*60
  @secret "JWT_SECRET"
  @salt "JWT_SALT"

  def create_otp_and_token(data) do
    otp = create_otp()
    signer = get_signer(otp)
    token = sign(data, signer)

    %{token: token, otp: otp}
  end

  def verify_token_with_otp(token, otp) do
    signer = get_signer(otp)

    verify(token, signer)
  end

  def create_otp(len \\ @default_otp_len) do
    otp =
      10 ** len
      |> :rand.uniform()
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    otp
  end

  defp sign(data, signer) do
    salt = get_salt()
    Phoenix.Token.sign(signer, salt, data)
  end

  defp verify(token, signer) do
    salt = get_salt()
    Phoenix.Token.verify(signer, salt, token, max_age: @max_age)
  end

  defp get_signer(otp) do
    secret = get_secret()
    secret <> otp
  end

  defp get_secret() do
    System.get_env(@secret)
  end

  defp get_salt() do
    System.get_env(@salt)
  end

end
