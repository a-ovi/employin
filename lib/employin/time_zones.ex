defmodule Employin.TimeZones do
  @moduledoc """
  IANA time zone helpers. Times are stored in UTC and converted to the
  viewer's zone (sent by the browser, e.g. `"Asia/Dhaka"`) with the `tz`
  database, so DST transitions are handled correctly.
  """

  @default "Etc/UTC"

  def default, do: @default

  @doc "Returns `zone` if it is a known IANA zone, otherwise `default/0`."
  @spec normalize(term()) :: String.t()
  def normalize(zone) when is_binary(zone) do
    case DateTime.shift_zone(DateTime.utc_now(), zone) do
      {:ok, _} -> zone
      {:error, _} -> @default
    end
  end

  def normalize(_zone), do: @default

  @spec to_local(DateTime.t(), String.t()) :: DateTime.t()
  def to_local(%DateTime{} = utc, zone), do: DateTime.shift_zone!(utc, zone)

  @spec local_date(DateTime.t(), String.t()) :: Date.t()
  def local_date(%DateTime{} = utc, zone), do: utc |> to_local(zone) |> DateTime.to_date()

  @spec local_today(String.t()) :: Date.t()
  def local_today(zone), do: local_date(DateTime.utc_now(), zone)

  @doc """
  Converts a local wall-clock date and time in `zone` to UTC.

  Times that occur twice (DST ends) resolve to the first occurrence. Times
  that don't exist (DST starts) resolve to the first valid instant after the gap.
  """
  @spec local_to_utc(Date.t(), Time.t(), String.t()) :: DateTime.t()
  def local_to_utc(%Date{} = date, %Time{} = time, zone) do
    local =
      case DateTime.new(date, Time.truncate(time, :second), zone) do
        {:ok, datetime} -> datetime
        {:ambiguous, first, _second} -> first
        {:gap, _just_before, just_after} -> just_after
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end
end
