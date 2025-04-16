defmodule Employin.Repo.Migrations.AddUserTable do
  use Ecto.Migration

  def up do
    create table("users") do
      add :display_name, :string, null: false
      add :email, :string, null: false

      timestamps()
    end
  end

  def down do
    drop table("users")
  end
end
