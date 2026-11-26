defmodule Employin.Events do
  @moduledoc """
  The Events context: recording when users start and end work.

  Rules:

    * A user's events must alternate `joined` → `left` → `joined` … in time.
    * Quick events (`toggle_status/2`) always happen "now".
    * Past work sessions (`create_work_session/4`) must fit into a gap where
      the user was not working, and they never overlap other events.
    * Sessions can be moved (`update_work_session/5`) or deleted
      (`delete_work_session/2`) by their owner under the same rules.

  Writes for one user are serialized with a transaction-scoped Postgres
  advisory lock, so concurrent tabs can't break the alternation. Every
  write is broadcast on the `"events"` PubSub topic as
  `{:new_events, [%Event{user: %User{}}, ...]}` (oldest first), once per command.
  Edits and deletes broadcast `{:events_changed, user_id}`.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Employin.Events.Event
  alias Employin.Repo

  @topic "events"
  @default_limit 30

  ## PubSub

  def subscribe, do: Phoenix.PubSub.subscribe(Employin.PubSub, @topic)

  defp broadcast(events) when is_list(events) do
    Phoenix.PubSub.broadcast(Employin.PubSub, @topic, {:new_events, events})
  end

  # Edits and deletes can move or remove events anywhere in the log.
  defp broadcast_change(user_id) do
    Phoenix.PubSub.broadcast(Employin.PubSub, @topic, {:events_changed, user_id})
  end

  ## Queries

  @doc """
  Lists events of all users in chronological order (oldest first), with users preloaded.

  Options:

    * `:limit` – the newest `limit` matching events (default #{@default_limit}, `nil` for all)
    * `:before` – `{time, id}` cursor: only events strictly before it (keyset pagination)
    * `:since` – `{time, id}` cursor: only events at or after it
  """
  def list_events(opts \\ []) do
    Event
    |> before_cursor(opts[:before])
    |> since_cursor(opts[:since])
    |> order_by([e], desc: e.time, desc: e.id)
    |> maybe_limit(Keyword.get(opts, :limit, @default_limit))
    |> preload(:user)
    |> Repo.all()
    |> Enum.reverse()
  end

  defp before_cursor(query, nil), do: query

  defp before_cursor(query, {time, id}) do
    where(query, [e], e.time < ^time or (e.time == ^time and e.id < ^id))
  end

  defp since_cursor(query, nil), do: query

  defp since_cursor(query, {time, id}) do
    where(query, [e], e.time > ^time or (e.time == ^time and e.id >= ^id))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc "The latest event of a user, or `nil`."
  def last_event(user_id) do
    Event
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.time, desc: e.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc ~S|`"joined"` if the given (latest) event means the user is working, else `"left"`.|
  def current_status(nil), do: Event.left()
  def current_status(%{type: type}), do: type

  @doc "The location of the current work session, or `\"\"` when not working."
  def current_location(%{type: type, tags: tags}) when is_binary(type) do
    if type == Event.joined(), do: tags || "", else: ""
  end

  def current_location(_event), do: ""

  ## Commands

  @doc """
  Starts work if the user isn't working, otherwise ends it.

  `tags` is the location for a new session. When ending work, the location of
  the running session is kept.
  """
  def toggle_status(user_id, tags \\ nil) do
    Multi.new()
    |> lock_user(user_id)
    |> Multi.run(:event, fn repo, _ ->
      last = last_event(user_id)

      attrs =
        if current_status(last) == Event.joined() do
          %{type: Event.left(), tags: current_location(last)}
        else
          %{type: Event.joined(), tags: tags}
        end

      %Event{user_id: user_id}
      |> Event.changeset(attrs)
      |> repo.insert()
    end)
    |> transact()
    |> case do
      {:ok, %{event: event}} -> {:ok, event |> List.wrap() |> publish() |> hd()}
      {:error, :event, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Records a past work session as a `joined`/`left` pair.

  Returns `{:error, :overlap}` if the range overlaps other events or
  falls inside a running session.
  """
  def create_work_session(user_id, %DateTime{} = starting, %DateTime{} = ending, tags \\ nil) do
    Multi.new()
    |> lock_user(user_id)
    |> Multi.run(:slot, fn _repo, _ ->
      if slot_available?(user_id, starting, ending), do: {:ok, :free}, else: {:error, :overlap}
    end)
    |> Multi.insert(:joined, session_event(user_id, Event.joined(), starting, tags))
    |> Multi.insert(:left, session_event(user_id, Event.left(), ending, tags))
    |> transact()
    |> case do
      {:ok, %{joined: joined, left: left}} -> {:ok, publish([joined, left])}
      {:error, :slot, :overlap, _} -> {:error, :overlap}
      {:error, _step, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Finds the work session (`joined` + following `left`) that contains the
  given event of the user. `left` is `nil` for the session in progress.
  """
  def get_work_session(user_id, event_id) do
    with {:ok, event_id} <- Ecto.UUID.cast(event_id),
         %Event{} = event <- Repo.get_by(Event, id: event_id, user_id: user_id) do
      session_around(event)
    else
      _ -> {:error, :not_found}
    end
  end

  defp session_around(%Event{type: "joined"} = joined) do
    case adjacent_event(joined, :next) do
      nil -> {:ok, %{joined: joined, left: nil}}
      %Event{type: "left"} = left -> {:ok, %{joined: joined, left: left}}
      _other -> {:error, :not_found}
    end
  end

  defp session_around(%Event{type: "left"} = left) do
    case adjacent_event(left, :previous) do
      %Event{type: "joined"} = joined -> {:ok, %{joined: joined, left: left}}
      _other -> {:error, :not_found}
    end
  end

  defp adjacent_event(event, direction) do
    query = where(Event, [e], e.user_id == ^event.user_id and e.id != ^event.id)

    query =
      case direction do
        :next ->
          query
          |> where([e], e.time > ^event.time or (e.time == ^event.time and e.id > ^event.id))
          |> order_by([e], asc: e.time, asc: e.id)

        :previous ->
          query
          |> where([e], e.time < ^event.time or (e.time == ^event.time and e.id < ^event.id))
          |> order_by([e], desc: e.time, desc: e.id)
      end

    query |> limit(1) |> Repo.one()
  end

  @doc """
  Moves a work session and/or changes its location.

  `ending` must be `nil` for the session in progress and a datetime otherwise.
  The same overlap rules as `create_work_session/4` apply, ignoring the
  session's own events.
  """
  def update_work_session(user_id, event_id, %DateTime{} = starting, ending, tags) do
    Multi.new()
    |> lock_user(user_id)
    |> Multi.run(:session, fn _repo, _ -> get_work_session(user_id, event_id) end)
    |> Multi.run(:slot, fn _repo, %{session: session} ->
      check_session_slot(user_id, session, starting, ending)
    end)
    |> Multi.run(:joined, fn repo, %{session: %{joined: joined}} ->
      joined |> Event.changeset(%{time: starting, tags: tags}) |> repo.update()
    end)
    |> Multi.run(:left, fn repo, %{session: %{left: left}} ->
      if left,
        do: left |> Event.changeset(%{time: ending, tags: tags}) |> repo.update(),
        else: {:ok, nil}
    end)
    |> transact()
    |> case do
      {:ok, %{joined: joined, left: left}} ->
        broadcast_change(user_id)
        {:ok, %{joined: joined, left: left}}

      {:error, _step, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc "Deletes a work session (both events), or cancels the session in progress."
  def delete_work_session(user_id, event_id) do
    Multi.new()
    |> lock_user(user_id)
    |> Multi.run(:session, fn _repo, _ -> get_work_session(user_id, event_id) end)
    |> Multi.run(:delete, fn repo, %{session: %{joined: joined, left: left}} ->
      ids = Enum.reject([joined.id, left && left.id], &is_nil/1)
      {count, _} = repo.delete_all(where(Event, [e], e.id in ^ids))
      {:ok, count}
    end)
    |> transact()
    |> case do
      {:ok, _} ->
        broadcast_change(user_id)
        :ok

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp check_session_slot(user_id, %{joined: joined, left: left}, starting, ending) do
    except = Enum.reject([joined.id, left && left.id], &is_nil/1)

    cond do
      is_nil(left) != is_nil(ending) -> {:error, :invalid}
      slot_available?(user_id, starting, ending, except) -> {:ok, :free}
      true -> {:error, :overlap}
    end
  end

  @doc """
  True if `[starting, ending]` contains no events of the user, the event right
  before it is a `left` (or there is none), and the event right after it is a
  `joined` (or there is none).

  With `ending = nil` (a session still in progress) no event may follow
  `starting`. Events in `except` (the session being edited) are ignored.
  """
  def slot_available?(user_id, starting, ending, except \\ []) do
    user_events = where(Event, [e], e.user_id == ^user_id and e.id not in ^except)

    previous =
      user_events
      |> where([e], e.time < ^starting)
      |> order_by([e], desc: e.time)
      |> limit(1)
      |> Repo.one()

    next =
      if ending do
        user_events
        |> where([e], e.time > ^ending)
        |> order_by([e], asc: e.time)
        |> limit(1)
        |> Repo.one()
      end

    inside? =
      if ending do
        user_events |> where([e], e.time >= ^starting and e.time <= ^ending) |> Repo.exists?()
      else
        user_events |> where([e], e.time >= ^starting) |> Repo.exists?()
      end

    not inside? and
      (is_nil(previous) or previous.type == Event.left()) and
      (is_nil(next) or next.type == Event.joined())
  end

  defp session_event(user_id, type, time, tags) do
    Event.changeset(%Event{user_id: user_id}, %{type: type, time: time, tags: tags})
  end

  defp lock_user(multi, user_id) do
    Multi.run(multi, :lock, fn repo, _ ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [to_string(user_id)])
      {:ok, :locked}
    end)
  end

  defp transact(multi), do: Repo.transaction(multi)

  defp publish(events) do
    events = Repo.preload(events, :user)
    broadcast(events)
    events
  end
end
