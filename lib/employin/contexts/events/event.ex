defmodule Employin.Events.Event do
  use Employin.Schema

  import Ecto.Changeset

  @joined "joined"
  @left "left"
  @valid_event_types [@left, @joined]

  schema "events" do
    field :type, :string
    field :time, :utc_datetime
    belongs_to :user, Employin.Users.User

    timestamps()
  end

  def changeset(event, params) do
    event
    |> cast(params, [:type, :time])
    |> validate_required(:type)
    |> validate_inclusion(:type, @valid_event_types)
  end

  def joined() do
    @joined
  end

  def left() do
    @left
  end

end
