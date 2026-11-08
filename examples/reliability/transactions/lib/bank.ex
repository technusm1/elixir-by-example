defmodule Bank do
  alias Bank.{Account, Repo, Transfer}
  alias Ecto.Multi

  def open(name, balance), do: Repo.insert(Account.open(name, balance))

  def balances do
    Account |> Repo.all() |> Map.new(&{&1.name, &1.balance})
  end

  def account(name), do: Repo.get_by!(Account, name: name)

  # A transfer is three writes: debit, credit, and a row
  # recording it under its idempotency key. `Ecto.Multi`
  # runs them in one transaction. If any step fails,
  # none of them happened.
  def transfer(key, from_name, to_name, amount) do
    from = account(from_name)
    to = account(to_name)

    Multi.new()
    |> Multi.update(:debit, Account.adjust(from, -amount))
    |> Multi.update(:credit, Account.adjust(to, amount))
    |> Multi.insert(:record, Transfer.record(key, from, to, amount))
    |> Repo.transact()
    |> case do
      {:ok, _changes} -> :ok
      {:error, step, changeset, _done} -> {:error, step, errors(changeset)}
    end
  end

  # Read-modify-write with optimistic locking. If someone
  # else changed the row since `account` was read, the
  # update matches no row and raises instead of
  # overwriting their change.
  def deposit_locked(account, amount) do
    Repo.update(Account.adjust_locked(account, amount))
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
