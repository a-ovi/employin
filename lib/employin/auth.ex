defmodule Employin.Auth do
  @moduledoc """
  Rules of the passwordless login flow on top of `Employin.LoginToken`:

    * at most a few login codes per email address per window,
    * at most a few code guesses per issued token,
    * login links and post-registration tokens can be used only once.
  """
  import Ecto.Query, warn: false

  alias Employin.LoginToken
  alias Employin.RateLimit
  alias Employin.Repo

  # Used tokens only need to be remembered while they could still verify.
  @remember_used_for_seconds 10 * 60

  @doc "Issues a new OTP and token for `email`, unless too many were requested recently."
  @spec request_code(String.t()) ::
          {:ok, %{otp: String.t(), token: String.t()}} | {:error, {:rate_limited, integer()}}
  def request_code(email) do
    with :ok <- RateLimit.check(:send_code, String.downcase(email)) do
      {:ok, LoginToken.create_otp_and_token(email)}
    end
  end

  @doc "Checks a code without consuming the token. Every call counts as an attempt."
  @spec verify_code(term(), term()) ::
          {:ok, String.t()} | {:error, :invalid | :expired | {:rate_limited, integer()}}
  def verify_code(token, otp) when is_binary(token) do
    with :ok <- RateLimit.check(:verify_code, token_hash(token) |> Base.url_encode64()) do
      LoginToken.verify_otp(token, otp)
    end
  end

  def verify_code(_token, _otp), do: {:error, :invalid}

  @doc "Like `verify_code/2`, but the token can't be used again afterwards."
  @spec consume_code(term(), term()) ::
          {:ok, String.t()} | {:error, :invalid | :expired | :used | {:rate_limited, integer()}}
  def consume_code(token, otp) do
    with {:ok, email} <- verify_code(token, otp),
         :ok <- mark_used(token) do
      {:ok, email}
    end
  end

  @doc "Verifies and consumes a `:session` token issued after registration."
  @spec consume_session_token(term()) :: {:ok, term()} | {:error, :invalid | :expired | :used}
  def consume_session_token(token) do
    with {:ok, user_id} <- LoginToken.verify(:session, token),
         :ok <- mark_used(token) do
      {:ok, user_id}
    end
  end

  defp mark_used(token) do
    now = DateTime.utc_now(:second)
    cutoff = DateTime.add(now, -@remember_used_for_seconds)
    Repo.delete_all(from t in "used_login_tokens", where: t.used_at < ^cutoff)

    case Repo.insert_all("used_login_tokens", [%{token_hash: token_hash(token), used_at: now}],
           on_conflict: :nothing
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :used}
    end
  end

  defp token_hash(token), do: :crypto.hash(:sha256, token)
end
