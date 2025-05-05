defmodule Employin.Repo.Migrations.AddTagsColumnToEventsTable do
  use Ecto.Migration

  def up do
    alter table(:events) do
      add :tags, :string, default: ""
    end
  end

  def down do
    alter table(:events) do
      remove :tags
    end
  end
end
