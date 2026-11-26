defmodule Employin.Repo.Migrations.BackfillEventTimeAndAddIndexes do
  use Ecto.Migration

  # `events.time` used to be optional and every query fell back to
  # `COALESCE(time, inserted_at)`, which no index can serve. Backfill it,
  # make it required and index the access paths used by the app.
  def up do
    execute "UPDATE events SET time = inserted_at WHERE time IS NULL"

    alter table(:events) do
      modify :time, :utc_datetime, null: false
    end

    create index(:events, [:time])
    create index(:events, [:user_id, :time])
  end

  def down do
    drop index(:events, [:user_id, :time])
    drop index(:events, [:time])

    alter table(:events) do
      modify :time, :utc_datetime, null: true
    end
  end
end
