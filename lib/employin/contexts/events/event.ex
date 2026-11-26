defmodule Employin.Events.Event do
  @moduledoc """
  A single attendance event: a user either `"joined"` (started work) or
  `"left"` (ended work) at `time`, tagged with a location. A `"joined"` event
  without a location gets `default_tag/0`, and a `"left"` event repeats the
  location of the session it ends.

  Besides the schema changeset, this module provides `session_form_changeset/3`.
  It backs the "add past work session" form, which collects local dates and
  times and is converted to a UTC range in the browser's IANA time zone.
  """
  use Employin.Schema

  import Ecto.Changeset

  alias Employin.TimeZones

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

  @doc "Location used when a work session is started without one."
  def default_tag, do: hd(@tags)

  def changeset(event, params) do
    event
    |> cast(params, [:type, :time, :tags])
    |> put_default_time()
    |> put_default_tags()
    |> validate_required([:type, :time])
    |> validate_inclusion(:type, @types)
    |> validate_tags()
  end

  @doc """
  Changeset for the work-session form (add or edit). `time_zone` is the
  viewer's IANA zone (e.g. `"Asia/Dhaka"`) and `now` is injectable for tests.

  With `running?: true` (editing the session in progress) only the start is
  collected, and it must not be in the future.
  """
  def session_form_changeset(
        params,
        time_zone \\ "Etc/UTC",
        now \\ DateTime.utc_now(),
        opts \\ []
      ) do
    running? = Keyword.get(opts, :running?, false)
    required = if running?, do: [:starting_date, :starting_time], else: @session_required

    {%{}, @session_types}
    |> cast(params, Map.keys(@session_types))
    |> validate_required(required)
    |> validate_tags()
    |> validate_session_range(time_zone, now, running?)
  end

  @doc """
  Validates the session form and returns the UTC range on success
  (`ending` is `nil` with `running?: true`).
  """
  def apply_session_form(params, time_zone, now \\ DateTime.utc_now(), opts \\ []) do
    changeset = session_form_changeset(params, time_zone, now, opts)

    with {:ok, _} <- apply_action(changeset, :validate) do
      {:ok,
       %{
         starting: local_field_to_utc(changeset, :starting, time_zone),
         ending: unless(opts[:running?], do: local_field_to_utc(changeset, :ending, time_zone)),
         tags: get_field(changeset, :tags)
       }}
    end
  end

  @doc "Form params (local date/time strings) for an existing session."
  def session_form_params(%__MODULE__{} = joined, left, time_zone) do
    %{"tags" => joined.tags}
    |> Map.merge(local_params(:starting, joined.time, time_zone))
    |> Map.merge(if left, do: local_params(:ending, left.time, time_zone), else: %{})
  end

  defp local_params(prefix, utc, time_zone) do
    local = TimeZones.to_local(utc, time_zone)

    %{
      "#{prefix}_date" => local |> DateTime.to_date() |> Date.to_iso8601(),
      "#{prefix}_time" => local |> DateTime.to_time() |> Calendar.strftime("%H:%M")
    }
  end

  defp validate_session_range(%{valid?: false} = changeset, _time_zone, _now, _running?),
    do: changeset

  defp validate_session_range(changeset, time_zone, now, true = _running?) do
    starting = local_field_to_utc(changeset, :starting, time_zone)

    if DateTime.compare(starting, now) == :gt do
      add_error(changeset, :starting_time, "can't be in the future")
    else
      changeset
    end
  end

  defp validate_session_range(changeset, time_zone, now, false = _running?) do
    starting = local_field_to_utc(changeset, :starting, time_zone)
    ending = local_field_to_utc(changeset, :ending, time_zone)

    cond do
      DateTime.compare(ending, starting) != :gt ->
        add_error(changeset, :ending_time, "must be after the start")

      DateTime.compare(ending, now) == :gt ->
        add_error(changeset, :ending_time, "can't be in the future")

      true ->
        changeset
    end
  end

  defp local_field_to_utc(changeset, prefix, time_zone) do
    TimeZones.local_to_utc(
      get_field(changeset, :"#{prefix}_date"),
      get_field(changeset, :"#{prefix}_time"),
      time_zone
    )
  end

  defp put_default_time(changeset) do
    if get_field(changeset, :time) do
      changeset
    else
      put_change(changeset, :time, DateTime.utc_now(:second))
    end
  end

  # Every work session has a location: a "joined" event without one gets the default.
  defp put_default_tags(changeset) do
    if get_field(changeset, :type) == @joined and is_nil(get_field(changeset, :tags)) do
      put_change(changeset, :tags, default_tag())
    else
      changeset
    end
  end

  defp validate_tags(changeset), do: validate_inclusion(changeset, :tags, @tags)
end
