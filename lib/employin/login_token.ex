defmodule Employin.LoginToken do
  @moduledoc """
  Stateless signed tokens used by the passwordless login flow.

  Every token is bound to a *purpose* so that a token issued for one step of
  the flow can never be replayed in another one:

    * `:otp` – emailed together with a one-time password. The OTP is mixed
      into the signing key, so the token is only valid with the matching code.
    * `:registration` – carries the verified email address of a new user
      to the profile setup page.
    * `:session` – carries a user id from the registration LiveView to the
      session controller, which turns it into a cookie session.
    * `:pending` – *encrypted* state of a login in progress (email, OTP token,
      time sent), kept in the login page URL so a refresh doesn't lose it.

  Configuration (see `config/*.exs` and `config/runtime.exs`):

      config :employin, Employin.LoginToken,
        secret: "at least 32 random bytes",
        salt: "employin"
  """

  @otp_length 6

  @purposes %{
    otp: %{salt: "otp login", max_age: 5 * 60},
    registration: %{salt: "registration", max_age: 10 * 60},
    session: %{salt: "session login", max_age: 60},
    pending: %{salt: "pending login", max_age: 5 * 60}
  }

  @type purpose :: :otp | :registration | :session | :pending

  @doc "Creates a fresh OTP and a token that can only be verified with it."
  @spec create_otp_and_token(String.t()) :: %{otp: String.t(), token: String.t()}
  def create_otp_and_token(email) do
    otp = generate_otp()
    %{otp: otp, token: sign(:otp, email, otp)}
  end

  @doc "Verifies an `:otp` token against the code entered by the user."
  @spec verify_otp(term(), term()) :: {:ok, String.t()} | {:error, atom()}
  def verify_otp(token, otp) when is_binary(token) and is_binary(otp) do
    verify(:otp, token, String.trim(otp))
  end

  def verify_otp(_token, _otp), do: {:error, :invalid}

  @doc "Generates a cryptographically secure, zero-padded numeric code."
  @spec generate_otp() :: String.t()
  def generate_otp do
    <<n::unsigned-integer-size(32)>> = :crypto.strong_rand_bytes(4)

    n
    |> rem(10 ** @otp_length)
    |> Integer.to_string()
    |> String.pad_leading(@otp_length, "0")
  end

  @doc "Signs `data` for the given purpose."
  @spec sign(purpose(), term(), String.t()) :: String.t()
  def sign(purpose, data, key_suffix \\ "") do
    Phoenix.Token.sign(secret() <> key_suffix, salt(purpose), data)
  end

  @doc "Verifies a token issued with `sign/3` for the same purpose."
  @spec verify(purpose(), term(), String.t()) :: {:ok, term()} | {:error, atom()}
  def verify(purpose, token, key_suffix \\ "")

  def verify(purpose, token, key_suffix) when is_binary(token) do
    %{max_age: max_age} = Map.fetch!(@purposes, purpose)
    Phoenix.Token.verify(secret() <> key_suffix, salt(purpose), token, max_age: max_age)
  end

  def verify(_purpose, _token, _key_suffix), do: {:error, :invalid}

  @doc "Encrypts `data` for the given purpose (the payload is not readable by the client)."
  @spec encrypt(purpose(), term()) :: String.t()
  def encrypt(purpose, data) do
    Phoenix.Token.encrypt(secret(), salt(purpose), data)
  end

  @doc "Decrypts a token issued with `encrypt/2` for the same purpose."
  @spec decrypt(purpose(), term()) :: {:ok, term()} | {:error, atom()}
  def decrypt(purpose, token) when is_binary(token) do
    %{max_age: max_age} = Map.fetch!(@purposes, purpose)
    Phoenix.Token.decrypt(secret(), salt(purpose), token, max_age: max_age)
  end

  def decrypt(_purpose, _token), do: {:error, :invalid}

  defp salt(purpose) do
    %{salt: salt} = Map.fetch!(@purposes, purpose)
    "#{config(:salt, "employin")} #{salt}"
  end

  defp secret, do: config(:secret) || raise("#{inspect(__MODULE__)} :secret is not configured")

  defp config(key, default \\ nil) do
    :employin
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
