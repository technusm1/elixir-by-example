Everything so far kept its state in process memory, and a restart lost it.
Data that must survive goes in a database, and most databases speak SQL.
[Ecto](https://ecto.hexdocs.pm/Ecto.html) is how Elixir programs talk to them.
Rows come back as plain structs, every write is checked before it reaches the
database, queries are Elixir code that you build up piece by piece, and
migrations keep the tables' shape in version control. Ecto is not an ORM: a
struct is just data, with no connection behind it, and nothing is loaded
behind your back (Ecto doesn't lazy load). Every trip to the database is a
call you can see.

This track uses SQLite through the `ecto_sqlite3` adapter, so the whole
database is one file and there's nothing to install. The code is the same on
Postgres, apart from the adapter.

On this page:

1. The four pieces: a *repo*, a *migration*, a *schema* and a *changeset*.
2. Inserting rows, and reading why a write was refused.
3. Reading, updating and deleting, and queries with `from`.

## The project

A tiny library catalog with one table, `books`. The only dependency is the
SQLite adapter, which brings in `ecto` (schemas, changesets, queries) and
`ecto_sql` (migrations, SQL databases).

```file mix.exs
```

`ecto_repos` is for the `mix ecto.*` tasks: it tells them which repos to
create and migrate. The second line configures the repo itself.

```file config/config.exs
```

The **repo** is your handle on one database. `use Ecto.Repo` gives the module
`insert`, `get`, `all`, `update`, `delete` and the rest; `otp_app:` says where
its config lives and `adapter:` which database it talks to.

```file lib/library/repo.ex
```

A repo is also a process: it owns a pool of database connections, so it goes
in the application's supervision tree like any other child.

```file lib/library/application.ex
```

A **migration** changes the database's shape. Its file name starts with a
timestamp, and Ecto runs pending migrations in that order and records which
ones ran, so every copy of the database ends up with the same tables.

```file priv/repo/migrations/20261108000000_create_books.exs
```

A **schema** maps a table to a struct, and a **changeset** is a proposed
change to one: `cast/3` takes the allowed fields from outside data (a form, a
JSON body) and converts them to the field types, then the `validate_*`
functions check them. `unique_constraint/2` checks nothing by itself: it tells
Ecto that if the unique index refuses the write, return an error instead of
raising.

```file lib/library/book.ex
```

The `Library` module wraps the repo calls. `alias Library.{Book, Repo}` is
two aliases in one line.

```file lib/library.ex
```

## Set up

Fetching and compiling the dependencies prints progress and timings, so that
output is hidden. `ecto.create` creates the database (here, the file
`library.db`) and `ecto.migrate` runs the migration. Migrations open two
connections by default; `--pool-size 1` keeps it to one, because SQLite takes
one writer at a time and two connections opening a fresh file can fail with
"database is locked".

```sh
mix deps.get > /dev/null
mix deps.compile > /dev/null 2>&1
mix compile
mix ecto.create --quiet
mix ecto.migrate --quiet --pool-size 1
```

## Inserting

A schema's struct is an ordinary struct, plus `__meta__`, where Ecto notes
whether it came from the database (`:built` means not yet). `Repo.insert/1`
returns `{:ok, book}` with the `id` the database gave it. The second book
arrives the way a web form would send it, with string keys and `"264"` as a
string; `cast/3` turns that into the integer 264.

```sh
mix run -e '
IO.inspect(%Library.Book{title: "Dune"})
{:ok, book} = Library.add_book(%{title: "Dune", author: "Frank Herbert", pages: 412})
IO.inspect({book.id, book.title, book.pages}, label: "inserted")
{:ok, book} = Library.add_book(%{"title" => "Kindred", "author" => "Octavia E. Butler", "pages" => "264"})
IO.inspect({book.id, book.title, book.pages}, label: "inserted")
{:ok, _} = Library.add_book(%{title: "The Dispossessed", author: "Ursula K. Le Guin", pages: 387})
{:ok, _} = Library.add_book(%{title: "A Wizard of Earthsea", author: "Ursula K. Le Guin", pages: 183})
'
```

## When a write is refused

A failed write returns `{:error, changeset}`, and nothing reaches the
database. The changeset's `errors` hold each message with a template
(`%{count}`) and its values; `Ecto.Changeset.traverse_errors/2` (used in
`Library.errors/1`) turns them into a map of readable messages.

The last two lines show the order of checks: a second "Dune" passes every
validation, so it reaches the database and the unique index refuses it. With
a bad page count as well, validation fails first and the database is never
asked, so the duplicate title isn't reported.

```sh
mix run -e '
{:error, changeset} = Library.add_book(%{title: "X", pages: -5})
IO.inspect(changeset)
IO.inspect(Library.errors(changeset))
{:error, changeset} = Library.add_book(%{title: "Dune", author: "Someone Else"})
IO.inspect(Library.errors(changeset))
{:error, changeset} = Library.add_book(%{title: "Dune", author: "Someone Else", pages: -1})
IO.inspect(Library.errors(changeset))
'
```

## Reading, updating, deleting

`Repo.get/2` fetches by id and returns `nil` if there's no such row
(`Repo.get!/2` raises instead). `Repo.all/1` takes a schema for every row, or
a query. `Library.titles_by/1` uses the keyword syntax, one `from` with
`where:`, `order_by:` and `select:`; `Library.shorter_than/1` builds a query
with the pipe syntax, one step at a time. Both mean the same thing. In both,
`^` (the pin from [Pattern Matching](/core/pattern-matching)) brings an
Elixir value into the query; Ecto sends it to the database as a parameter,
never as SQL text.

```sh
mix run -e '
IO.inspect(Library.Repo.get(Library.Book, 1).title)
IO.inspect(Library.Repo.get(Library.Book, 99))
IO.inspect(length(Library.Repo.all(Library.Book)), label: "books")
IO.inspect(Library.titles_by("Ursula K. Le Guin"))
IO.inspect(Library.shorter_than(300))
'
```

Updates go through the same changeset as inserts, so the same rules apply,
and `Repo.update/1` writes only the fields that changed. `Repo.delete/1`
takes the struct to delete.

```sh
mix run -e '
{:ok, book} = Library.set_pages("Dune", 896)
IO.inspect(book.pages, label: "Dune pages")
{:ok, _} = Library.remove("Kindred")
IO.inspect(Library.shorter_than(1000))
'
```

## Going further

That's enough Ecto for the rest of this track. For more:

- Ecto's [Getting Started](https://ecto.hexdocs.pm/getting-started.html)
  guide, and the docs for
  [`Ecto.Query`](https://ecto.hexdocs.pm/Ecto.Query.html),
  [`Ecto.Changeset`](https://ecto.hexdocs.pm/Ecto.Changeset.html) and
  [`Ecto.Migration`](https://ecto-sql.hexdocs.pm/Ecto.Migration.html).
- SQL itself, as SQLite understands it:
  [SQL As Understood By SQLite](https://www.sqlite.org/lang.html).

> **Pitfall:** a validation only sees the data in front of it. Two requests
> can both check "is this title free?" and both pass. Rules that must hold
> under concurrent writes belong in the database (a unique index, a `CHECK`),
> with `unique_constraint/2` or `check_constraint/3` turning the refusal into
> a changeset error. [Transactions and Constraints](/reliability/transactions)
> shows this.

> **Pitfall:** only fields listed in `cast/3` can come from outside data.
> That's the point: never cast fields a user shouldn't set (an `admin` flag,
> a balance). Set those in code, with `change/2` or `put_change/3`.
