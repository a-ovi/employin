defmodule Employin.Repo.Migrations.CreateUsedLoginTokens do
  use Ecto.Migration

  # Login links are single-use: a token's SHA-256 is recorded when it is used.
  def change do
    create table(:used_login_tokens, primary_key: false) do
      add :token_hash, :binary, primary_key: true
      add :used_at, :utc_datetime, null: false
    end

    create index(:used_login_tokens, [:used_at])
  end
end
