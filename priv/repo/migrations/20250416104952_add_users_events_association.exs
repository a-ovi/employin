defmodule Employin.Repo.Migrations.AddUsersEventsAssociation do
  use Ecto.Migration

  def up do
    alter table("events") do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end
  end

  def down do
    alter table("events") do
      remove :user_id
    end
  end
end
