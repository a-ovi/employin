defmodule Employin.Users.User do
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

  def change_email(email, params, opts \\ []) do
    email
    |> cast(params, [:email])
    |> validate_email(opts)
  end

  def change_display_name(name, params) do
    name
    |> cast(params, [:display_name])
    |> validate_display_name()
  end


  def validate_display_name(changeset) do
    changeset
    |> validate_required(:display_name)
    |> validate_format(:display_name, ~r/^[A-Za-z ]+$/, message: "only alphabetic characters")
    |> validate_length(:display_name, min: @min_display_name_length, max: @max_display_name_length)
  end

  def validate_email(changeset, _opts \\ []) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, get_email_regex(), message: "invalid email format")
    |> validate_length(:email, max: 64)
    # |> maybe_validate_unique_email(opts)
  end

  def maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Employin.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
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
