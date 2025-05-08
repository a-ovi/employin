defmodule Employin.Repo.Migrations.ConvertEmailToCitext do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    alter table("users") do
      modify :email, :citext, null: false
    end

    create unique_index("users", [:email])
  end

  def down do
    drop_if_exists index("users", [:email])

    alter table("users") do
      modify :email, :string, null: false
    end
  end
end
