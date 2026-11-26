defmodule Employin.EventsTest do
  use Employin.DataCase, async: true

  alias Employin.Events
  alias Employin.Events.Event

  setup do
    %{user: user_fixture()}
  end

  describe "toggle_status/2" do
    test "alternates between joined and left and keeps the session location", %{user: user} do
      assert {:ok, %Event{type: "joined", tags: "Remote"}} =
               Events.toggle_status(user.id, "Remote")

      assert {:ok, %Event{type: "left", tags: "Remote"}} =
               Events.toggle_status(user.id, "On-site")

      assert {:ok, %Event{type: "joined", tags: "On-site"}} =
               Events.toggle_status(user.id, "On-site")
    end

    test "starts work at the default location when none is given", %{user: user} do
      assert {:ok, %Event{type: "joined", tags: "Remote"}} = Events.toggle_status(user.id, nil)
      assert Event.default_tag() == "Remote"
    end

    test "rejects unknown locations", %{user: user} do
      assert {:error, changeset} = Events.toggle_status(user.id, "Moon")
      assert "is invalid" in errors_on(changeset).tags
    end

    test "broadcasts the new event with its user", %{user: user} do
      Events.subscribe()
      {:ok, %Event{id: id}} = Events.toggle_status(user.id, nil)

      assert_receive {:new_event, %Event{id: ^id, user: %{email: email}}}
      assert email == user.email
    end
  end

  describe "current_status/1 and current_location/1" do
    test "derive the state from the latest event", %{user: user} do
      assert Events.current_status(nil) == "left"
      assert Events.current_location(nil) == ""

      joined = event_fixture(user, "joined", minutes_from_now(-10), "On-site")
      assert Events.current_status(joined) == "joined"
      assert Events.current_location(joined) == "On-site"

      left = event_fixture(user, "left", minutes_from_now(-5), "On-site")
      assert Events.last_event(user.id).id == left.id
      assert Events.current_location(left) == ""
    end
  end

  describe "create_work_session/4" do
    test "inserts a joined/left pair", %{user: user} do
      starting = minutes_from_now(-120)
      ending = minutes_from_now(-60)

      assert {:ok, [joined, left]} =
               Events.create_work_session(user.id, starting, ending, "Remote")

      assert {joined.type, joined.time, joined.tags} == {"joined", starting, "Remote"}
      assert {left.type, left.time} == {"left", ending}
    end

    test "fits into a gap between two sessions", %{user: user} do
      event_fixture(user, "joined", minutes_from_now(-600))
      event_fixture(user, "left", minutes_from_now(-500))
      event_fixture(user, "joined", minutes_from_now(-100))

      assert {:ok, _} =
               Events.create_work_session(user.id, minutes_from_now(-400), minutes_from_now(-300))
    end

    test "rejects ranges that contain events", %{user: user} do
      event_fixture(user, "joined", minutes_from_now(-90))
      event_fixture(user, "left", minutes_from_now(-80))

      assert {:error, :overlap} =
               Events.create_work_session(user.id, minutes_from_now(-120), minutes_from_now(-60))
    end

    test "rejects ranges inside a running session", %{user: user} do
      event_fixture(user, "joined", minutes_from_now(-240))

      assert {:error, :overlap} =
               Events.create_work_session(user.id, minutes_from_now(-120), minutes_from_now(-60))

      assert [_only_the_fixture] = Events.list_events()
    end

    test "other users' events don't count as overlaps", %{user: user} do
      other = user_fixture()
      event_fixture(other, "joined", minutes_from_now(-90))

      assert {:ok, _} =
               Events.create_work_session(user.id, minutes_from_now(-120), minutes_from_now(-60))
    end
  end

  describe "list_events/1" do
    test "returns events oldest-first with keyset pagination", %{user: user} do
      events =
        for minutes <- 50..1//-1 do
          event_fixture(user, Enum.random(["joined", "left"]), minutes_from_now(-minutes))
        end

      page1 = Events.list_events(limit: 20)
      assert Enum.map(page1, & &1.id) == events |> Enum.take(-20) |> Enum.map(& &1.id)
      assert hd(page1).user.email == user.email

      [oldest | _] = page1
      page2 = Events.list_events(limit: 20, before: {oldest.time, oldest.id})
      assert Enum.map(page2, & &1.id) == events |> Enum.slice(10, 20) |> Enum.map(& &1.id)
    end

    test "orders events with the same time by id", %{user: user} do
      time = minutes_from_now(-1)
      a = event_fixture(user, "joined", time)
      b = event_fixture(user, "left", time)

      assert Enum.map(Events.list_events(), & &1.id) == Enum.sort([a.id, b.id])

      assert Events.list_events(before: {time, max(a.id, b.id)}) |> Enum.map(& &1.id) == [
               min(a.id, b.id)
             ]
    end
  end

  describe "Event.apply_session_form/3" do
    @now ~U[2026-05-10 12:00:00Z]

    test "converts local date and time to UTC" do
      params = %{
        "starting_date" => "2026-05-10",
        "starting_time" => "09:00",
        "ending_date" => "2026-05-10",
        "ending_time" => "17:30",
        "tags" => "Remote"
      }

      # UTC+6: 09:00 local is 03:00 UTC.
      assert {:ok, %{starting: ~U[2026-05-10 03:00:00Z], ending: ~U[2026-05-10 11:30:00Z]}} =
               Event.apply_session_form(params, 360, @now)
    end

    test "requires the end to be after the start and not in the future" do
      base = %{"starting_date" => "2026-05-10", "ending_date" => "2026-05-10"}

      assert {:error, changeset} =
               Event.apply_session_form(
                 Map.merge(base, %{"starting_time" => "10:00", "ending_time" => "09:00"}),
                 0,
                 @now
               )

      assert "must be after the start" in errors_on(changeset).ending_time

      assert {:error, changeset} =
               Event.apply_session_form(
                 Map.merge(base, %{"starting_time" => "10:00", "ending_time" => "13:00"}),
                 0,
                 @now
               )

      assert "can't be in the future" in errors_on(changeset).ending_time
    end

    test "requires all date and time fields" do
      assert {:error, changeset} = Event.apply_session_form(%{}, 0, @now)

      assert %{starting_date: _, starting_time: _, ending_date: _, ending_time: _} =
               errors_on(changeset)
    end
  end
end
