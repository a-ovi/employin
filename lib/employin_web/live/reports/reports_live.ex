defmodule EmployinWeb.ReportsLive do
  @moduledoc """
  Hours worked per user per day for a week or a month, in the viewer's time
  zone, with CSV export. The page follows `/reports?period=week|month&date=...`
  and recomputes when events change.
  """
  use EmployinWeb, :live_view

  alias Employin.Events
  alias Employin.Reports
  alias Employin.TimeZones
  alias EmployinWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Events.subscribe()

    time_zone =
      case get_connect_params(socket) do
        %{"timezone" => zone} -> TimeZones.normalize(zone)
        _ -> TimeZones.default()
      end

    {:ok, socket |> assign(:page_title, "Reports") |> assign(:time_zone, time_zone)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    period = if params["period"] == "month", do: :month, else: :week

    anchor =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, date} -> date
        _ -> TimeZones.local_today(socket.assigns.time_zone)
      end

    {first, last} =
      if period == :month, do: Reports.month_of(anchor), else: Reports.week_of(anchor)

    {:noreply,
     socket
     |> assign(period: period, anchor: anchor, first: first, last: last)
     |> load_report()}
  end

  @impl true
  def handle_info({event, _payload}, socket) when event in [:new_events, :events_changed] do
    {:noreply, load_report(socket)}
  end

  # The browser's time zone is only known once connected, so the first
  # (static) render shows a spinner instead of a report in UTC.
  defp load_report(socket) do
    report =
      if connected?(socket) do
        %{first: first, last: last, time_zone: time_zone} = socket.assigns
        {:ok, report} = Reports.worked_time(first, last, time_zone)
        report
      end

    assign(socket, :report, report)
  end

  ## Template helpers

  defp period_path(period, date),
    do: ~p"/reports?#{[period: period, date: Date.to_iso8601(date)]}"

  defp shift(:week, date, n), do: Date.add(date, 7 * n)
  defp shift(:month, date, n), do: Date.shift(date, month: n)

  defp range_label(:month, first, _last), do: Calendar.strftime(first, "%B %Y")

  defp range_label(:week, first, last) do
    "#{Calendar.strftime(first, "%b %d")} – #{Calendar.strftime(last, "%b %d, %Y")}"
  end

  defp format_duration(0), do: "–"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)

    "#{div(minutes, 60)}:#{minutes |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp csv_path(first, last, time_zone) do
    ~p"/reports/export.csv?#{[from: Date.to_iso8601(first), to: Date.to_iso8601(last), tz: time_zone]}"
  end
end
