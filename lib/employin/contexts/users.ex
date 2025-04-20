defmodule Employin.Users do
  import Ecto.Query, warn: false

  alias Employin.Users.User
  alias Employin.Repo
  alias Ecto.Changeset

  def get_all() do
    Repo.all(User)
  end

  def get(id) do
    Repo.get(User, id)
  end

  def get_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def get_by_email!(email) do
    Repo.get_by!(User, email: email)
  end

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def delete_by_email(email) do
    case get_by_email(email) do
      nil ->
        {
          :error,
          %User{}
          |> Changeset.change()
          |> Changeset.add_error(:email, "User not found")
        }
      user ->
        Repo.delete(user)
    end
  end
end
