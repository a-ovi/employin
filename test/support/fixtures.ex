defmodule Employin.Fixtures do
  @moduledoc "Test data builders."

  alias Employin.Events.Event
  alias Employin.Repo
  alias Employin.Users

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{email: unique_email(), display_name: "Test User"})
      |> Users.create_user()

    user
  end

  @doc "Inserts an event directly, bypassing the business rules in `Employin.Events`."
  def event_fixture(user, type, %DateTime{} = time, tags \\ nil) do
    %Event{user_id: user.id}
    |> Event.changeset(%{type: type, time: time, tags: tags})
    |> Repo.insert!()
  end

  @doc "A UTC datetime `minutes` from now, truncated to seconds."
  def minutes_from_now(minutes) do
    DateTime.utc_now(:second) |> DateTime.add(minutes, :minute)
  end
end
