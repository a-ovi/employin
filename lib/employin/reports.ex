defmodule Employin.Reports do
  @moduledoc """
  Worked-time reports built from `joined`/`left` events.

  A work session runs from a `joined` event to the following `left` event of
  the same user. A session still in progress counts until `now`. Sessions are
  clipped to the report range and split at local midnight, so time worked
  across midnight counts towards both days in the viewer's time zone.
  """
  import Ecto.Query, warn: false

  alias Employin.Events.Event
  alias Employin.Repo
  alias Employin.TimeZones
  alias Employin.Users.User

  @max_days 366

  @type row :: %{
          user: User.t(),
          seconds_by_date: %{Date.t() => non_neg_integer()},
          total_seconds: non_neg_integer()
        }

  @doc """
  Seconds worked per user per local date, for every date in `first..last`
  (inclusive) in `time_zone`.

  Returns `%{dates: [Date.t()], rows: [row], total_seconds: integer}` with one
  row per user, sorted by display name, or `{:error, :range_too_long}` for
  ranges over #{@max_days} days.
  """
  def worked_time(%Date{} = first, %Date{} = last, time_zone, now \\ DateTime.utc_now()) do
    if Date.diff(last, first) >= @max_days or Date.compare(last, first) == :lt do
      {:error, :range_too_long}
    else
      range_start = TimeZones.local_to_utc(first, ~T[00:00:00], time_zone)
      range_end = TimeZones.local_to_utc(Date.add(last, 1), ~T[00:00:00], time_zone)
      until = Enum.min([now, range_end], DateTime)

      seconds =
        range_start
        |> events_for_range(range_end)
        |> Enum.group_by(& &1.user_id)
        |> Map.new(fn {user_id, events} ->
          {user_id, user_seconds(events, range_start, until, time_zone)}
        end)

      rows =
        User
        |> order_by([u], asc: u.display_name, asc: u.email)
        |> Repo.all()
        |> Enum.map(fn user ->
          by_date = Map.get(seconds, user.id, %{})

          %{
            user: user,
            seconds_by_date: by_date,
            total_seconds: by_date |> Map.values() |> Enum.sum()
          }
        end)

      {:ok,
       %{
         dates: Enum.to_list(Date.range(first, last)),
         rows: rows,
         total_seconds: rows |> Enum.map(& &1.total_seconds) |> Enum.sum()
       }}
    end
  end

  @doc "Monday-to-Sunday week containing `date`."
  def week_of(%Date{} = date) do
    first = Date.beginning_of_week(date, :monday)
    {first, Date.add(first, 6)}
  end

  @doc "Calendar month containing `date`."
  def month_of(%Date{} = date), do: {Date.beginning_of_month(date), Date.end_of_month(date)}

  # Events inside the range, plus each user's last event before it, so that a
  # session that started before the range is counted from the range start.
  defp events_for_range(range_start, range_end) do
    before_range =
      from e in Event,
        where: e.time < ^range_start,
        distinct: e.user_id,
        order_by: [asc: e.user_id, desc: e.time, desc: e.id]

    in_range =
      from e in Event,
        where: e.time >= ^range_start and e.time < ^range_end,
        order_by: [asc: e.time, asc: e.id]

    Repo.all(before_range) ++ Repo.all(in_range)
  end

  defp user_seconds(events, range_start, until, time_zone) do
    events
    |> Enum.sort_by(&{DateTime.to_unix(&1.time), &1.id})
    |> sessions(until)
    |> Enum.flat_map(fn {from, to} -> clip({from, to}, range_start, until) end)
    |> Enum.flat_map(&split_by_local_day(&1, time_zone))
    |> Enum.reduce(%{}, fn {date, seconds}, acc ->
      Map.update(acc, date, seconds, &(&1 + seconds))
    end)
  end

  # Pairs joined -> left. A second "joined" while one is open is ignored.
  defp sessions(events, until) do
    {sessions, open} =
      Enum.reduce(events, {[], nil}, fn
        %{type: "joined", time: time}, {acc, nil} ->
          {acc, time}

        %{type: "joined"}, {acc, open} ->
          {acc, open}

        %{type: "left", time: time}, {acc, open} when not is_nil(open) ->
          {[{open, time} | acc], nil}

        %{type: "left"}, {acc, nil} ->
          {acc, nil}
      end)

    sessions = if open, do: [{open, until} | sessions], else: sessions
    Enum.reverse(sessions)
  end

  defp clip({from, to}, range_start, range_end) do
    from = Enum.max([from, range_start], DateTime)
    to = Enum.min([to, range_end], DateTime)
    if DateTime.compare(to, from) == :gt, do: [{from, to}], else: []
  end

  defp split_by_local_day({from, to}, time_zone) do
    date = TimeZones.local_date(from, time_zone)
    next_midnight = TimeZones.local_to_utc(Date.add(date, 1), ~T[00:00:00], time_zone)

    if DateTime.compare(to, next_midnight) == :gt do
      [
        {date, DateTime.diff(next_midnight, from)}
        | split_by_local_day({next_midnight, to}, time_zone)
      ]
    else
      [{date, DateTime.diff(to, from)}]
    end
  end
end
