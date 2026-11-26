defmodule EmployinWeb.HomeLive.ActivityLog do
  @moduledoc """
  Keeps the activity log in a LiveView stream (`@streams.log`), so the server
  doesn't hold every loaded event in memory.

  The stream holds two kinds of items in chronological order:

    * `%{kind: :divider, id: "date-<date>-<event id>", date: date}` – a sticky
      day header, placed before the first event of each local day
    * `%{kind: :event, id: "event-<id>", event: view}` – an event

  Since the stream's contents can't be read back, `@log_window` remembers
  only the edges of what has been rendered:

      %{oldest: %{time:, id:, date:, divider_id:}, newest: %{time:, id:, date:}}

  This is enough to:

    * prepend an older page, removing the old first divider if the page ends
      on the same day,
    * append a live event, adding a divider when it starts a new day,
    * detect an event that belongs inside the window (e.g. a past session).
      The caller then reloads the window with `reset/3`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_configure: 3, stream_delete_by_dom_id: 3]

  alias Employin.TimeZones

  def init(socket) do
    socket
    |> stream_configure(:log, dom_id: & &1.id)
    |> stream(:log, [], reset: true)
    |> assign(:log_window, nil)
  end

  @doc "Replaces the log with `events` (oldest first). `fresh_ids` get highlighted."
  def reset(socket, events, fresh_ids \\ []) do
    items = to_items(events, socket.assigns.time_zone, nil, fresh_ids)

    socket
    |> stream(:log, items, reset: true)
    |> assign(:log_window, window(events, items, socket.assigns.time_zone))
  end

  @doc "Adds an older page (oldest first) above the current log."
  def prepend(socket, []), do: socket

  def prepend(socket, events) do
    %{time_zone: time_zone, log_window: window} = socket.assigns
    items = to_items(events, time_zone, nil, [])
    last_date = events |> List.last() |> local_date(time_zone)

    # The page continues the current first day, so its divider moves up.
    socket =
      if window && window.oldest.date == last_date do
        stream_delete_by_dom_id(socket, :log, window.oldest.divider_id)
      else
        socket
      end

    new_window =
      case window do
        nil -> window(events, items, time_zone)
        window -> %{window | oldest: oldest_edge(events, items, time_zone)}
      end

    # Each item is inserted at index 0 in turn, so insert the page newest-first.
    socket
    |> stream(:log, Enum.reverse(items), at: 0)
    |> assign(:log_window, new_window)
  end

  @doc """
  Decides where live events (oldest first) go: `:append` (all newer than the
  log), `:reload` (some fall inside the loaded window) or `:ignore` (all older
  than everything loaded; "load more" shows them).
  """
  def placement(nil, _events), do: :append

  def placement(%{oldest: oldest, newest: newest}, [first | _] = events) do
    cond do
      compare(first, newest) != :lt -> :append
      Enum.any?(events, &(compare(&1, oldest) != :lt)) -> :reload
      true -> :ignore
    end
  end

  @doc "Appends live events (oldest first) at the bottom and highlights them."
  def append(socket, events) do
    %{time_zone: time_zone, log_window: window} = socket.assigns
    previous_date = window && window.newest.date
    items = to_items(events, time_zone, previous_date, Enum.map(events, & &1.id))

    new_window =
      case window do
        nil -> window(events, items, time_zone)
        window -> %{window | newest: edge(List.last(events), time_zone)}
      end

    socket
    |> stream(:log, items, at: -1)
    |> assign(:log_window, new_window)
  end

  @doc "The `{time, id}` cursor of the oldest loaded event, or nil."
  def oldest_cursor(%{log_window: %{oldest: %{time: time, id: id}}}), do: {time, id}
  def oldest_cursor(_assigns), do: nil

  ## Items

  defp to_items(events, time_zone, previous_date, fresh_ids) do
    {items, _date} =
      Enum.flat_map_reduce(events, previous_date, fn event, previous ->
        date = local_date(event, time_zone)

        item = %{
          kind: :event,
          id: "event-#{event.id}",
          event: to_view(event, event.id in fresh_ids)
        }

        if date == previous do
          {[item], date}
        else
          {[%{kind: :divider, id: "date-#{date}-#{event.id}", date: date}, item], date}
        end
      end)

    items
  end

  defp to_view(event, fresh?) do
    %{
      id: event.id,
      user_id: event.user_id,
      type: event.type,
      tags: event.tags,
      time: event.time,
      fresh?: fresh?,
      user: %{
        display_name: event.user && event.user.display_name,
        email: event.user && event.user.email
      }
    }
  end

  ## Window

  defp window([], _items, _time_zone), do: nil

  defp window(events, items, time_zone) do
    %{
      oldest: oldest_edge(events, items, time_zone),
      newest: edge(List.last(events), time_zone)
    }
  end

  defp oldest_edge([first | _], [%{kind: :divider, id: divider_id} | _], time_zone) do
    first |> edge(time_zone) |> Map.put(:divider_id, divider_id)
  end

  defp edge(event, time_zone) do
    %{time: event.time, id: event.id, date: local_date(event, time_zone)}
  end

  defp local_date(event, time_zone), do: TimeZones.local_date(event.time, time_zone)

  defp compare(event, edge) do
    case DateTime.compare(event.time, edge.time) do
      :eq -> compare_ids(event.id, edge.id)
      other -> other
    end
  end

  defp compare_ids(a, b) when a < b, do: :lt
  defp compare_ids(a, b) when a > b, do: :gt
  defp compare_ids(_a, _b), do: :eq
end
