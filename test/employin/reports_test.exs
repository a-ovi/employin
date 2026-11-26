defmodule Employin.ReportsTest do
  use Employin.DataCase, async: true

  alias Employin.Reports

  # Fixed "now" so the expectations don't depend on the clock.
  @now ~U[2026-03-12 12:00:00Z]

  defp hours(report, user, date) do
    row = Enum.find(report.rows, &(&1.user.id == user.id))
    Map.get(row.seconds_by_date, date, 0) / 3600
  end

  setup do
    %{user: user_fixture(%{display_name: "Alice Anderson"})}
  end

  test "sums sessions per local day", %{user: user} do
    event_fixture(user, "joined", ~U[2026-03-10 09:00:00Z])
    event_fixture(user, "left", ~U[2026-03-10 12:00:00Z])
    event_fixture(user, "joined", ~U[2026-03-10 13:00:00Z])
    event_fixture(user, "left", ~U[2026-03-10 17:30:00Z])

    {:ok, report} = Reports.worked_time(~D[2026-03-09], ~D[2026-03-15], "Etc/UTC", @now)

    assert length(report.dates) == 7
    assert hours(report, user, ~D[2026-03-10]) == 7.5
    assert report.total_seconds == round(7.5 * 3600)
  end

  test "splits sessions at local midnight", %{user: user} do
    # 22:00–02:00 in Asia/Dhaka (UTC+6) on the night of March 10th.
    event_fixture(user, "joined", ~U[2026-03-10 16:00:00Z])
    event_fixture(user, "left", ~U[2026-03-10 20:00:00Z])

    {:ok, report} = Reports.worked_time(~D[2026-03-09], ~D[2026-03-15], "Asia/Dhaka", @now)

    assert hours(report, user, ~D[2026-03-10]) == 2.0
    assert hours(report, user, ~D[2026-03-11]) == 2.0
  end

  test "clips sessions to the range and counts a running session until now", %{user: user} do
    # Started the day before the range...
    event_fixture(user, "joined", ~U[2026-03-08 20:00:00Z])
    event_fixture(user, "left", ~U[2026-03-09 02:00:00Z])
    # ...and one still running.
    event_fixture(user, "joined", ~U[2026-03-12 08:00:00Z])

    {:ok, report} = Reports.worked_time(~D[2026-03-09], ~D[2026-03-15], "Etc/UTC", @now)

    assert hours(report, user, ~D[2026-03-08]) == 0
    assert hours(report, user, ~D[2026-03-09]) == 2.0
    assert hours(report, user, ~D[2026-03-12]) == 4.0
  end

  test "includes every user, sorted by name", %{user: user} do
    zed = user_fixture(%{display_name: "Zed Zimmerman"})

    {:ok, report} = Reports.worked_time(~D[2026-03-09], ~D[2026-03-15], "Etc/UTC", @now)

    assert Enum.map(report.rows, & &1.user.id) == [user.id, zed.id]
    assert Enum.all?(report.rows, &(&1.total_seconds == 0))
  end

  test "rejects reversed or overly long ranges" do
    assert {:error, :range_too_long} =
             Reports.worked_time(~D[2026-03-10], ~D[2026-03-09], "Etc/UTC")

    assert {:error, :range_too_long} =
             Reports.worked_time(~D[2025-01-01], ~D[2026-03-09], "Etc/UTC")
  end

  test "week_of/1 and month_of/1" do
    assert Reports.week_of(~D[2026-03-12]) == {~D[2026-03-09], ~D[2026-03-15]}
    assert Reports.month_of(~D[2026-02-10]) == {~D[2026-02-01], ~D[2026-02-28]}
  end
end
