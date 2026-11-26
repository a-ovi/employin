defmodule Employin.Events do
  @moduledoc """
  The Events context: recording when users start and end work.

  Rules:

    * A user's events must alternate `joined` → `left` → `joined` … in time.
    * Quick events (`toggle_status/2`) always happen "now".
    * Past work sessions (`create_work_session/4`) must fit into a gap where
      the user was not working, and they never overlap other events.

  Writes for one user are serialized with a transaction-scoped Postgres
  advisory lock, so concurrent tabs can't break the alternation. Every
  write is broadcast on the `"events"` PubSub topic as
  `{:new_events, [%Event{user: %User{}}, ...]}` (oldest first), once per command.
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
  True if `[starting, ending]` contains no events of the user, the event right
  before it is a `left` (or there is none), and the event right after it is a
  `joined` (or there is none).
  """
  def slot_available?(user_id, starting, ending) do
    user_events = where(Event, [e], e.user_id == ^user_id)

    previous =
      user_events
      |> where([e], e.time < ^starting)
      |> order_by([e], desc: e.time)
      |> limit(1)
      |> Repo.one()

    next =
      user_events
      |> where([e], e.time > ^ending)
      |> order_by([e], asc: e.time)
      |> limit(1)
      |> Repo.one()

    inside? =
      user_events
      |> where([e], e.time >= ^starting and e.time <= ^ending)
      |> Repo.exists?()

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
