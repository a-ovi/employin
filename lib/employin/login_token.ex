defmodule Employin.LoginToken do

  @default_otp_len 6
  @max_age 5*60
  @secret_name "JWT_SECRET"
  @salt_name "JWT_SALT"

  def create_otp_and_token(data) do
    otp = create_otp()
    signer = get_signer(otp)
    token = sign(data, signer: signer)

    %{token: token, otp: otp}
  end

  def verify_token_with_otp(token, otp) do
    signer = get_signer(otp)

    verify(token, signer: signer)
  end

  def create_otp(len \\ @default_otp_len) do
    otp =
      10 ** len
      |> :rand.uniform()
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    otp
  end

  def sign(data, opts \\ []) do
    signer = Keyword.get(opts, :signer, get_secret())
    salt = get_salt()
    Phoenix.Token.sign(signer, salt, data)
  end

  def verify(token, opts \\ []) do
    signer = Keyword.get(opts, :signer, get_secret())
    max_age = Keyword.get(opts, :max_age, @max_age)
    salt = get_salt()
    Phoenix.Token.verify(signer, salt, token, max_age: max_age)
  end

  defp get_signer(otp) do
    secret = get_secret()
    secret <> otp
  end

  defp get_secret() do
    System.get_env(@secret_name)
  end

  defp get_salt() do
    System.get_env(@salt_name)
  end

end
