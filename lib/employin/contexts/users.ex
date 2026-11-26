defmodule Employin.Users do
  @moduledoc "The Users context: lookup and registration of users."

  alias Ecto.Changeset
  alias Employin.Repo
  alias Employin.Users.User

  def get_all, do: Repo.all(User)

  @doc "Fetches a user by id. Returns `nil` for unknown or malformed ids."
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(User, uuid)
      :error -> nil
    end
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
