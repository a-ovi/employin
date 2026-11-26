defmodule EmployinWeb.ReportController do
  @moduledoc "CSV export of the worked-time report (one row per person per day)."
  use EmployinWeb, :controller

  alias Employin.Reports
  alias Employin.TimeZones
  alias NimbleCSV.RFC4180, as: CSV

  def export(conn, %{"from" => from, "to" => to} = params) do
    time_zone = TimeZones.normalize(params["tz"])

    with {:ok, first} <- Date.from_iso8601(from),
         {:ok, last} <- Date.from_iso8601(to),
         {:ok, report} <- Reports.worked_time(first, last, time_zone) do
      send_download(conn, {:binary, to_csv(report)},
        filename: "employin-hours-#{first}-to-#{last}.csv",
        content_type: "text/csv"
      )
    else
      _ -> conn |> put_status(:bad_request) |> text("Invalid report range")
    end
  end

  def export(conn, _params) do
    conn |> put_status(:bad_request) |> text("Missing report range")
  end

  defp to_csv(report) do
    rows =
      for row <- report.rows,
          date <- report.dates,
          seconds = Map.get(row.seconds_by_date, date, 0),
          seconds > 0 do
        [
          row.user.display_name,
          row.user.email,
          Date.to_iso8601(date),
          :erlang.float_to_binary(seconds / 3600, decimals: 2)
        ]
      end

    [["Name", "Email", "Date", "Hours"] | rows]
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end
end
