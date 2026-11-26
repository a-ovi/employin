defmodule EmployinWeb.HomeLiveTest do
  # Not async: HomeLive subscribes to the global "events" PubSub topic.
  use EmployinWeb.ConnCase, async: false

  alias Employin.Events

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "shows the activity log", %{conn: conn, user: user} do
      event_fixture(user, "joined", minutes_from_now(-30), "Remote")

      {:ok, lv, _html} = live(conn, ~p"/")
      html = render_async(lv)

      assert html =~ "Started work"
      assert html =~ user.email
      assert html =~ "Currently Working"
      assert has_element?(lv, "#location-tag[disabled]")
      assert has_element?(lv, "#add-session-btn[disabled]")
    end

    test "starts and ends work", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)
      assert render(lv) =~ "No activity yet"

      lv |> form("#quick-event-form", quick_event: %{tags: "On-site"}) |> render_submit()
      assert render(lv) =~ "Currently Working"
      assert %{type: "joined", tags: "On-site"} = Events.last_event(user.id)

      lv |> form("#quick-event-form") |> render_submit()
      assert render(lv) =~ "Not Working"
      assert %{type: "left", tags: "On-site"} = Events.last_event(user.id)
    end

    test "only highlights events that arrive live", %{conn: conn} do
      other = user_fixture(%{display_name: "Other Person"})
      old = event_fixture(other, "joined", minutes_from_now(-60))

      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)
      refute has_element?(lv, "#event-#{old.id}[phx-mounted]")

      {:ok, live_event} = Events.toggle_status(other.id)
      assert render(lv) =~ "Ended work"
      assert has_element?(lv, "#event-#{live_event.id}[phx-mounted]")
    end

    test "adds a past work session", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)

      lv |> element("#add-session-btn") |> render_click()
      assert has_element?(lv, "#session-form")

      yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      params = %{
        starting_date: yesterday,
        starting_time: "09:00",
        ending_date: yesterday,
        ending_time: "17:00",
        tags: "Remote"
      }

      lv |> form("#session-form", session: params) |> render_submit()

      refute has_element?(lv, "#session-form")
      assert render(lv) =~ "Work session added."
      assert [%{type: "joined"}, %{type: "left"}] = Events.list_events()

      assert Events.last_event(user.id).time ==
               DateTime.new!(Date.add(Date.utc_today(), -1), ~T[17:00:00])

      # The same range again overlaps.
      lv |> element("#add-session-btn") |> render_click()
      html = lv |> form("#session-form", session: params) |> render_submit()
      assert html =~ "overlaps with your existing events"
    end

    test "loads older events on demand", %{conn: conn, user: user} do
      for minutes <- 40..1//-1 do
        event_fixture(
          user,
          if(rem(minutes, 2) == 0, do: "joined", else: "left"),
          minutes_from_now(-minutes)
        )
      end

      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)
      assert lv |> element("#events-list") |> render() |> count_events() == 30

      render_hook(lv, "load-more", %{})
      assert lv |> element("#events-list") |> render() |> count_events() == 40
      assert render(lv) =~ "No more events"
    end
  end

  defp count_events(html), do: length(Regex.scan(~r/<li id="event-/, html))
end
