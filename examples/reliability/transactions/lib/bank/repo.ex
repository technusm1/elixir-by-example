defmodule Bank.Repo do
  use Ecto.Repo, otp_app: :bank, adapter: Ecto.Adapters.SQLite3
end
