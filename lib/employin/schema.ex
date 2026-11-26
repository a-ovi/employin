defmodule Employin.Schema do
  @moduledoc """
  `use Employin.Schema` instead of `Ecto.Schema` to get UUIDv7 primary keys,
  binary-id foreign keys and `:utc_datetime` timestamps.
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      # ensuring uuid7 as primary key
      @primary_key {:id, Ecto.UUID, autogenerate: {Uniq.UUID, :uuid7, []}}

      @foreign_key_type :binary_id

      @timestamps_opts [type: :utc_datetime]
    end
  end
end
