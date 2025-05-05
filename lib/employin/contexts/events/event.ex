defmodule Employin.Events.Event do
  use Employin.Schema

  import Ecto.Changeset

  @joined "joined"
  @left "left"
  @tags ["Remote", "On-site"]
  @valid_event_types [@left, @joined]

  @time_points [:starting, :ending]
  @components [:date, :hour, :minute, :period]

  # Generate all fields
  @date_fields (for point <- @time_points, component <- @components do
                  :"#{point}_#{component}"
                end)

  # Pre-filter by component
  @date_only_fields for point <- @time_points, do: :"#{point}_date"
  @hour_only_fields for point <- @time_points, do: :"#{point}_hour"
  @minute_only_fields for point <- @time_points, do: :"#{point}_minute"
  @period_only_fields for point <- @time_points, do: :"#{point}_period"

  # Define field types for the date-related fields. all are strings here
  @date_field_types Map.from_keys(@date_fields, :string)

  @hours Enum.map(1..12, &Integer.to_string/1)
  @minutes Enum.map(0..59, &Integer.to_string/1)
  @periods ["am", "pm"]

  schema "events" do
    field :type, :string
    field :time, :utc_datetime
    field :tags, :string
    belongs_to :user, Employin.Users.User

    timestamps()
  end

  def changeset(event, params) do
    event
    |> cast(params, [:type, :time, :tags])
    |> validate_required(:type)
    |> validate_inclusion(:type, @valid_event_types)
    |> validate_tags()
  end

  def form_changeset(params) do
    {%{}, @date_field_types}
    |> cast(params, @date_fields)
    |> validate_required(@date_fields)
    |> validate_date(@date_only_fields)
    |> validate_hour(@hour_only_fields)
    |> validate_minute(@minute_only_fields)
    |> validate_period(@period_only_fields)
    |> validate_tags()
  end

  def joined() do
    @joined
  end

  def left() do
    @left
  end

  def tag(idx) do
    idx = max(1, idx)
    Enum.at(@tags, idx - 1)
  end

  def validate_date(changeset, fields) do
    fields = List.wrap(fields)

    Enum.reduce(fields, changeset, fn field, acc ->
      validate_change(acc, field, &check_iso_date_format/2)
    end)
  end

  def validate_hour(changeset, fields) do
    validate_inclusion_for_multiple_fields(
      changeset,
      fields,
      @hours,
      "Hour must be between 1 to 12"
    )
  end

  def validate_minute(changeset, fields) do
    validate_inclusion_for_multiple_fields(
      changeset,
      fields,
      @minutes,
      "Minute must be between 0 to 59"
    )
  end

  def validate_period(changeset, fields) do
    validate_inclusion_for_multiple_fields(
      changeset,
      fields,
      @periods,
      "Period must be AM or PM"
    )
  end

  def validate_tags(changeset) do
    validate_inclusion(changeset, :tags, @tags)
  end

  defp validate_inclusion_for_multiple_fields(changeset, fields, valid_values, message) do
    fields = List.wrap(fields)

    Enum.reduce(fields, changeset, fn field, acc ->
      validate_inclusion(acc, field, valid_values, message: message)
    end)
  end

  defp check_iso_date_format(field, value) do
    case Date.from_iso8601(value) do
      {:ok, _} -> []
      {:error, _} -> [{field, "Date is invalid!"}]
    end
  end
end
