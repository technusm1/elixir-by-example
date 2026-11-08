defmodule Bank.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :name, :string, null: false
      # The database itself refuses a negative balance.
      add :balance, :integer,
        null: false,
        check: %{name: "balance_not_negative", expr: "balance >= 0"}

      add :lock_version, :integer, null: false, default: 1
    end

    create unique_index(:accounts, [:name])

    create table(:transfers) do
      add :key, :string, null: false
      add :from_id, references(:accounts), null: false
      add :to_id, references(:accounts), null: false
      add :amount, :integer, null: false
    end

    # One row per idempotency key, enforced by the database.
    create unique_index(:transfers, [:key])
  end
end
