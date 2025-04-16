defmodule Employin.Repo do
  use Ecto.Repo,
    otp_app: :employin,
    adapter: Ecto.Adapters.Postgres
end
