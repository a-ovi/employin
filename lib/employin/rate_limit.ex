defmodule Employin.RateLimit do
  @moduledoc """
  Node-local fixed-window rate limiter (Hammer with an ETS backend).

  Limits are keyed by what an attacker can't rotate cheaply: the email
  address for sending codes, and the issued token for guessing codes.
  IP-based limits are not used because behind a reverse proxy every request
  would share the proxy's address.

  Defaults can be overridden per environment:

      config :employin, Employin.RateLimit, send_code: {:timer.minutes(15), 5}
  """
  use Hammer, backend: :ets

  @defaults %{
    # login emails per address
    send_code: {:timer.minutes(15), 5},
    # code guesses per issued token
    verify_code: {:timer.minutes(5), 5}
  }

  @type action :: :send_code | :verify_code

  @doc """
  Counts one attempt of `action` for `key`.

  Returns `:ok`, or `{:error, {:rate_limited, retry_after_ms}}` once the limit is reached.
  """
  @spec check(action(), String.t()) :: :ok | {:error, {:rate_limited, non_neg_integer()}}
  def check(action, key) do
    {scale_ms, limit} = limit(action)

    case hit("#{action}:#{key}", scale_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, {:rate_limited, retry_after_ms}}
    end
  end

  defp limit(action) do
    :employin
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(action, Map.fetch!(@defaults, action))
  end
end
