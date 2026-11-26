defmodule Employin.UsersTest do
  # Not async: one test changes the EMAIL_DOMAIN environment variable.
  use Employin.DataCase, async: false

  alias Employin.Users
  alias Employin.Users.User

  describe "create_user/1" do
    test "creates a user with valid attributes" do
      assert {:ok, %User{} = user} =
               Users.create_user(%{email: " jane@example.com ", display_name: "Jane Doe"})

      assert user.email == "jane@example.com"
      assert Users.get_by_email("JANE@example.com").id == user.id
    end

    test "validates the display name" do
      assert {:error, changeset} = Users.create_user(%{email: unique_email(), display_name: "J0"})
      errors = errors_on(changeset).display_name

      assert "only alphabetic characters" in errors
      assert "should be at least 5 character(s)" in errors
    end

    test "returns an error instead of raising for a duplicate email" do
      user = user_fixture()

      assert {:error, changeset} =
               Users.create_user(%{email: String.upcase(user.email), display_name: "Other User"})

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get/1" do
    test "returns nil for unknown or malformed ids" do
      assert Users.get(Ecto.UUID.generate()) == nil
      assert Users.get("not-a-uuid") == nil
    end
  end

  describe "EMAIL_DOMAIN restriction" do
    setup do
      System.put_env("EMAIL_DOMAIN", "acme.com")
      on_exit(fn -> System.delete_env("EMAIL_DOMAIN") end)
    end

    test "accepts the domain and its subdomains only" do
      assert User.change_email(%User{}, %{email: "a@acme.com"}).valid?
      assert User.change_email(%User{}, %{email: "a@eu.acme.com"}).valid?
      refute User.change_email(%User{}, %{email: "a@example.com"}).valid?
      refute User.change_email(%User{}, %{email: "a@notacme.com"}).valid?
    end
  end
end
