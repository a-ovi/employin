defmodule Employin.Events.Event do
  @moduledoc """
  A single attendance event: a user either `"joined"` (started work) or
  `"left"` (ended work) at `time`, optionally tagged with a location.

  Besides the schema changeset, this module provides `session_form_changeset/3`.
  It backs the "add past work session" form, which collects local dates and
  times and is converted to a UTC range with the browser's timezone offset.
  """
  use Employin.Schema

  import Ecto.Changeset

  @joined "joined"
  @left "left"
  @types [@joined, @left]
  @tags ["Remote", "On-site"]

  @session_types %{
    starting_date: :date,
    starting_time: :time,
    ending_date: :date,
    ending_time: :time,
    tags: :string
  }
  @session_required [:starting_date, :starting_time, :ending_date, :ending_time]

  schema "events" do
    field :type, :string
    field :time, :utc_datetime
    field :tags, :string
    belongs_to :user, Employin.Users.User

    timestamps()
  end

  def joined, do: @joined
  def left, do: @left
  def tags, do: @tags

  def changeset(event, params) do
    event
    |> cast(params, [:type, :time, :tags])
    |> put_default_time()
    |> validate_required([:type, :time])
    |> validate_inclusion(:type, @types)
    |> validate_tags()
  end

  @doc """
  Changeset for the past-session form. `tz_offset` is the browser's offset
  from UTC in minutes (e.g. `360` for UTC+6) and `now` is injectable for tests.
  """
  def session_form_changeset(params, tz_offset \\ 0, now \\ DateTime.utc_now()) do
    {%{}, @session_types}
    |> cast(params, Map.keys(@session_types))
    |> validate_required(@session_required)
    |> validate_tags()
    |> validate_session_range(tz_offset, now)
  end

  @doc """
  Validates the session form and returns the UTC range on success.
  """
  def apply_session_form(params, tz_offset, now \\ DateTime.utc_now()) do
    changeset = session_form_changeset(params, tz_offset, now)

    with {:ok, _} <- apply_action(changeset, :validate) do
      {starting, ending} = utc_range(changeset, tz_offset)
      {:ok, %{starting: starting, ending: ending, tags: get_field(changeset, :tags)}}
    end
  end

  defp validate_session_range(%{valid?: false} = changeset, _tz_offset, _now), do: changeset

  defp validate_session_range(changeset, tz_offset, now) do
    {starting, ending} = utc_range(changeset, tz_offset)

    cond do
      DateTime.compare(ending, starting) != :gt ->
        add_error(changeset, :ending_time, "must be after the start")

      DateTime.compare(ending, now) == :gt ->
        add_error(changeset, :ending_time, "can't be in the future")

      true ->
        changeset
    end
  end

  defp utc_range(changeset, tz_offset) do
    {
      local_to_utc(
        get_field(changeset, :starting_date),
        get_field(changeset, :starting_time),
        tz_offset
      ),
      local_to_utc(
        get_field(changeset, :ending_date),
        get_field(changeset, :ending_time),
        tz_offset
      )
    }
  end

  defp local_to_utc(date, time, tz_offset) do
    date
    |> DateTime.new!(Time.truncate(time, :second))
    |> DateTime.add(-tz_offset, :minute)
  end

  defp put_default_time(changeset) do
    if get_field(changeset, :time) do
      changeset
    else
      put_change(changeset, :time, DateTime.utc_now(:second))
    end
  end

  defp validate_tags(changeset), do: validate_inclusion(changeset, :tags, @tags)
end
