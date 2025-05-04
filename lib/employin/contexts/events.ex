defmodule Employin.Events do
  import Ecto.Query, warn: false

  alias Employin.Users
  alias Employin.Events.Event
  alias Employin.Repo

  def create_event(id, attrs) do
    # attrs = update_time_field_to_utc(attrs)

    Users.get(id)
    |> Ecto.build_assoc(:events)
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  def get_events(opts \\ []) do
    Event
    |> order_by([e], desc: fragment("COALESCE(?, ?)", e.time, e.inserted_at))
    |> paginate(opts)
    |> preload(:user)
    |> Repo.all()
    |> Enum.reverse()
  end

  def get_events_by_email(email) do
    email
    |> query_events_by_email()
    |> Repo.all()
  end

  def get_events_by_user_id(user_id) do
    user_id
    |> query_events_by_user_id()
    |> Repo.all()
  end

  def get_last_event_by_email(email) do
    query_events_by_email(email)
    |> limit(1)
    |> Repo.one()
  end

  def get_last_event_by_user_id(user_id) do
    query_events_by_user_id(user_id)
    |> limit(1)
    |> Repo.one()
  end

  def query_events_by_email(email) do
    user = Users.get_by_email!(email)
    query_events_by_user_id(user.id)
  end

  def query_events_by_user_id(user_id) do
    Event
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: fragment("COALESCE(?, ?)", e.time, e.inserted_at))
  end

  def current_status(user_id) do
    case get_last_event_by_user_id(user_id) do
      nil ->
        Event.left()

      event ->
        event.type
    end
  end

  def preload_user(event) do
    Repo.preload(event, :user)
  end

  def can_insert?(user_id, start_time, end_time) do
    # Find event immediately before the starting date
    before_starting_date_query =
      from e in Event,
        where: e.user_id == ^user_id,
        where: fragment("COALESCE(?, ?)", e.time, e.inserted_at) < ^start_time,
        order_by: [desc: fragment("COALESCE(?, ?)", e.time, e.inserted_at)],
        limit: 1

    last_event_before_starting_date = Repo.one(before_starting_date_query)

    # Find event immediately after the ending date
    after_ending_date_query =
      from e in Event,
        where: e.user_id == ^user_id,
        where: fragment("COALESCE(?, ?)", e.time, e.inserted_at) > ^end_time,
        order_by: [asc: fragment("COALESCE(?, ?)", e.time, e.inserted_at)],
        limit: 1

    first_event_after_ending_date = Repo.one(after_ending_date_query)

    # Get count of events between start_time and end_time (including both)
    between_count_query =
      from e in Event,
        where: e.user_id == ^user_id,
        where: fragment("COALESCE(?, ?)", e.time, e.inserted_at) >= ^start_time,
        where: fragment("COALESCE(?, ?)", e.time, e.inserted_at) <= ^end_time,
        select: count(e.id)

    between_count = Repo.one(between_count_query)

    no_events_between = between_count == 0

    valid_event_before =
      last_event_before_starting_date == nil ||
        last_event_before_starting_date.type == Event.left()

    valid_event_after =
      first_event_after_ending_date == nil ||
        first_event_after_ending_date.type == Event.joined()

    no_events_between && valid_event_before && valid_event_after
  end

  defp paginate(query, opts) do
    per_page = opts[:per_page]
    page = opts[:page] || 1

    if per_page do
      offset = (page - 1) * per_page

      query
      |> limit(^per_page)
      |> offset(^offset)
    else
      query
    end
  end

  def update_time_field_to_utc(attrs) do
    if Map.get(attrs, "time") do
      Map.update!(attrs, "time", &string_to_utc/1)
    else
      attrs
    end
  end

  def string_to_utc(%{"hour" => hour, "minute" => minute} = _time) do
    hour = convert_to_integer(hour)
    minute = convert_to_integer(minute)
    time = Time.new!(hour, minute, 0)

    Date.utc_today()
    |> NaiveDateTime.new!(time)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def convert_to_integer(value) do
    if is_integer(value) do
      value
    else
      {value, _} = Integer.parse(value)
      value
    end
  end
end
