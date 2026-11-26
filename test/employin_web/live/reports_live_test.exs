defmodule EmployinWeb.ReportsLiveTest do
  # Not async: ReportsLive subscribes to the global "events" PubSub topic.
  use EmployinWeb.ConnCase, async: false

  alias Employin.Events

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/reports")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "shows a week and navigates between periods", %{conn: conn, user: user} do
      event_fixture(user, "joined", ~U[2026-03-10 09:00:00Z])
      event_fixture(user, "left", ~U[2026-03-10 17:30:00Z])

      {:ok, lv, _html} = live(conn, ~p"/reports?period=week&date=2026-03-12")

      assert lv |> element("#report-range") |> render() =~ "Mar 09 – Mar 15, 2026"
      assert lv |> element("#report-row-#{user.id}") |> render() =~ "8:30"
      assert has_element?(lv, "#export-csv[href*='from=2026-03-09'][href*='to=2026-03-15']")

      lv |> element("a[aria-label='Next period']") |> render_click()
      assert_patch(lv, ~p"/reports?period=week&date=2026-03-19")
      refute lv |> element("#report-row-#{user.id}") |> render() =~ "8:30"

      lv |> element("a", "Month") |> render_click()
      assert lv |> element("#report-range") |> render() =~ "March 2026"
    end

    test "updates when events change", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/reports?period=week&date=2026-03-12")
      refute lv |> element("#report-row-#{user.id}") |> render() =~ "1:00"

      {:ok, _} =
        Events.create_work_session(user.id, ~U[2026-03-10 09:00:00Z], ~U[2026-03-10 10:00:00Z])

      assert lv |> element("#report-row-#{user.id}") |> render() =~ "1:00"
    end
  end
end
