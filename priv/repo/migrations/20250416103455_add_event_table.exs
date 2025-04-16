defmodule Employin.Repo.Migrations.AddEventTable do
  use Ecto.Migration

  def up do
    create table ("events") do
      add :type, :string, null: false
      add :time, :utc_datetime

      timestamps()
    end
  end

  def down do
    drop table("events")
  end
end
