Everything on the earlier pages kept its state in process memory, and
everything there was lost on a restart. Data that must survive goes in a
database, and the database brings a guarantee no process gives you on its
own: a *transaction*. Several writes either all happen or none of them do,
even if the program crashes halfway through.

This page uses [Ecto](https://hexdocs.pm/ecto) with SQLite, so the whole
database is one file and there's nothing to install. Everything shown works
the same on Postgres.

On this page:

1. A transfer between two accounts as one transaction with `Ecto.Multi`.
2. Constraints in the database (no negative balance, one row per idempotency
   key) that make bad writes impossible, not just unlikely.
3. A *lost update*, where two read-modify-write cycles overwrite each other,
   and optimistic locking, which catches it.

## The project

```file mix.exs
```

Query logging is switched off so the output below shows results, not SQL with
timings.

```file config/config.exs
```

```file lib/bank/repo.ex
```

```file lib/bank/application.ex
```

The migration puts the rules in the database itself: a `CHECK` that a balance
can't go below zero, and a unique index on the transfer's idempotency key.
Rules in the database hold no matter which code writes, and no matter how many
writers run at once.

```file priv/repo/migrations/20261108000000_create_accounts.exs
```

`check_constraint/3` and `unique_constraint/3` don't check anything themselves.
They tell Ecto that when the database refuses a write for that reason, it
should return a changeset error instead of raising.

```file lib/bank/account.ex
```

```file lib/bank/transfer.ex
```

`Bank.transfer/4` builds an `Ecto.Multi`: a list of named steps run in one
transaction. On failure it returns the step that failed, its errors, and the
steps that had already run (which were rolled back).

```file lib/bank.ex
```

## Set up

Fetching and compiling the dependencies prints download progress and timings,
so that output is hidden. `ecto.create` makes the SQLite file and
`ecto.migrate` creates the tables.

```sh
mix deps.get > /dev/null
mix deps.compile > /dev/null 2>&1
mix compile
mix ecto.create --quiet
mix ecto.migrate --quiet
mix run -e 'Bank.open("alice", 100); Bank.open("bob", 50); IO.inspect(Bank.balances())'
```

## All or nothing

A transfer that works: three writes, one transaction.

```sh
mix run -e 'IO.inspect(Bank.transfer("t-1", "alice", "bob", 30)); IO.inspect(Bank.balances())'
```

Bob tries to send more than he has. The `CHECK` refuses the debit, and the
transaction stops at the first step.

```sh
mix run -e 'IO.inspect(Bank.transfer("t-2", "bob", "alice", 500))'
```

Now the same transfer as before is sent again, under the same idempotency
key, as a client would after a lost reply. This time the debit and the credit
both *succeed*, and the last step, recording the key, fails on the unique
index. The transaction rolls back the two writes that had already happened.
The balances are exactly as they were: the retry did nothing, which is what a
retry of finished work should do.

```sh
mix run -e 'IO.inspect(Bank.transfer("t-1", "alice", "bob", 30)); IO.inspect(Bank.balances())'
```

## Lost updates

A transaction protects writes that happen together. It doesn't protect a
*read-modify-write* spread over time: read the row, compute a new value in
Elixir, write it back. Two such cycles that read the same row both write
"balance + 10" computed from the same old balance, and one deposit disappears.

```sh
mix run -e '
first = Bank.account("alice")
second = Bank.account("alice")
{:ok, _} = Bank.Repo.update(Bank.Account.adjust(first, 10))
{:ok, _} = Bank.Repo.update(Bank.Account.adjust(second, 10))
IO.inspect(Bank.balances(), label: "two deposits of 10")
'
```

Alice had 70 and got two deposits, but has 80. *Optimistic locking* fixes it.
Every update also checks and bumps `lock_version`
(`UPDATE ... WHERE id = ? AND lock_version = ?`). The second writer's version
is out of date, its update matches no row, and Ecto raises
`Ecto.StaleEntryError` (turned into `{:error, :stale}` in `Bank`). The caller
re-reads the row and tries again.

```sh
mix run -e '
first = Bank.account("alice")
second = Bank.account("alice")
{:ok, _} = Bank.deposit_locked(first, 10)
IO.inspect(Bank.deposit_locked(second, 10), label: "second writer")
IO.inspect(Bank.balances())
'
```

> **Pitfall:** validations in a changeset (`validate_number/3`) check the
> value *Elixir* computed, from data that may already be stale. Only a
> constraint in the database sees every write, including concurrent ones and
> ones from other programs. Keep the rule in the database and use
> `check_constraint/3` to turn the refusal into an error.

> **Pitfall:** the simplest fix for a lost update is to let the database do
> the arithmetic: `Repo.update_all(from(a in Account, where: a.id == ^id),
> inc: [balance: 10])`. There's no read, so there's nothing to go stale.
> Optimistic locking is for changes Elixir has to compute.

> **Pitfall:** don't do slow work (HTTP calls, sending email) inside a
> transaction. It holds locks the whole time, and if the transaction rolls
> back, the email was still sent. Record the intent in the transaction and do
> the work afterwards; [the outbox pattern](/reliability/outbox) is exactly that.
