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

    test "pre-selects a location for new sessions", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)

      # No "Select" placeholder: the default location is chosen.
      refute has_element?(lv, "#location-tag option[value='']")
      assert has_element?(lv, "#location-tag option[value='Remote'][selected]")

      # Submitting without touching the select starts work at the default location.
      lv |> form("#quick-event-form") |> render_submit()
      assert %{type: "joined", tags: "Remote"} = Events.last_event(user.id)

      # Ending and starting again pre-selects the last used location.
      lv |> form("#quick-event-form") |> render_submit()
      lv |> form("#quick-event-form", quick_event: %{tags: "On-site"}) |> render_submit()
      lv |> form("#quick-event-form") |> render_submit()
      assert has_element?(lv, "#location-tag option[value='On-site'][selected]")

      lv |> element("#add-session-btn") |> render_click()
      refute has_element?(lv, "#session_tags option[value='']")
      assert has_element?(lv, "#session_tags option[value='On-site'][selected]")
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

    test "loads older events on demand, in order, with one divider per day", %{
      conn: conn,
      user: user
    } do
      events =
        for hours <- 40..1//-1 do
          type = if rem(hours, 2) == 0, do: "joined", else: "left"
          event_fixture(user, type, minutes_from_now(-hours * 60))
        end

      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)
      assert lv |> log_html() |> event_ids() == events |> Enum.take(-30) |> Enum.map(& &1.id)

      render_hook(lv, "load-more", %{})
      html = log_html(lv)

      assert event_ids(html) == Enum.map(events, & &1.id)
      assert divider_dates(html) == events |> Enum.map(&DateTime.to_date(&1.time)) |> Enum.uniq()
      assert render(lv) =~ "No more events"
    end

    test "places a past session inside the loaded window in order", %{conn: conn, user: user} do
      other = user_fixture(%{display_name: "Other Person"})
      first = event_fixture(other, "joined", minutes_from_now(-600))
      last = event_fixture(other, "left", minutes_from_now(-60))

      {:ok, lv, _html} = live(conn, ~p"/")
      render_async(lv)

      {:ok, [joined, left]} =
        Events.create_work_session(user.id, minutes_from_now(-300), minutes_from_now(-240))

      assert lv |> log_html() |> event_ids() == [first.id, joined.id, left.id, last.id]
      assert has_element?(lv, "#event-#{joined.id}[phx-mounted]")
      refute has_element?(lv, "#event-#{first.id}[phx-mounted]")
    end
  end

  defp log_html(lv), do: lv |> element("#events-list") |> render()

  defp event_ids(html) do
    ~r/<li id="event-([0-9a-f-]+)"/ |> Regex.scan(html, capture: :all_but_first) |> List.flatten()
  end

  defp divider_dates(html) do
    ~r/<li id="date-(\d{4}-\d{2}-\d{2})-/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&Date.from_iso8601!/1)
  end
end
