defmodule Employin.Users.User do
  @moduledoc """
  A registered user. Emails are stored as `citext` and are unique.

  Registration can be limited to one email domain (and its subdomains)
  with the `EMAIL_DOMAIN` environment variable.
  """
  use Employin.Schema

  import Ecto.Changeset

  @min_display_name_length 5
  @max_display_name_length 25
  @email_regex ~r/^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

  schema "users" do
    field :display_name, :string
    field :email, :string
    has_many :events, Employin.Events.Event

    timestamps()
  end

  def changeset(user, params, opts \\ []) do
    user
    |> change_email(params, opts)
    |> change_display_name(params)
  end

  def change_email(user, params, _opts \\ []) do
    user
    |> cast(params, [:email])
    |> update_change(:email, &String.trim/1)
    |> validate_email()
    |> unique_constraint(:email)
  end

  def change_display_name(user, params) do
    user
    |> cast(params, [:display_name])
    |> update_change(:display_name, &String.trim/1)
    |> validate_display_name()
  end

  def validate_display_name(changeset) do
    changeset
    |> validate_required(:display_name)
    |> validate_format(:display_name, ~r/^[A-Za-z ]+$/, message: "only alphabetic characters")
    |> validate_length(:display_name,
      min: @min_display_name_length,
      max: @max_display_name_length
    )
  end

  def validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, get_email_regex(), message: "invalid email format")
    |> validate_length(:email, max: 64)
  end

  def get_email_regex() do
    case System.get_env("EMAIL_DOMAIN") do
      nil ->
        @email_regex

      "" ->
        @email_regex

      domain ->
        escaped_domain = Regex.escape(domain)
        Regex.compile!("^[a-zA-Z0-9._%+-]+@([a-zA-Z0-9.-]+\\.)?#{escaped_domain}$")
    end
  end
end
