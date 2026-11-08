defmodule Bank.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :name, :string
    field :balance, :integer
    field :lock_version, :integer, default: 1
  end

  def open(name, balance) do
    %Bank.Account{}
    |> change(name: name, balance: balance)
    |> unique_constraint(:name)
  end

  # `check_constraint/3` turns the database's refusal into
  # a changeset error instead of an exception.
  def adjust(account, delta) do
    account
    |> change(balance: account.balance + delta)
    |> check_constraint(:balance, name: :balance_not_negative, message: "would go negative")
  end

  # Same, plus optimistic locking: the update only
  # applies if `lock_version` is still what we read.
  def adjust_locked(account, delta) do
    account
    |> adjust(delta)
    |> optimistic_lock(:lock_version)
  end
end
