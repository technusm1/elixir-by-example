Every page so far was one file, run with `elixir file.exs`. Real programs have
many modules, tests, settings that differ between your laptop and production,
and code written by other people. *Mix*, the build tool that ships with Elixir,
handles all of that: it creates projects, compiles them, runs them and their
tests, formats the code and fetches dependencies.

On this page:

1. What `mix new` generates.
2. A small library, `bill`, that adds up and splits a restaurant bill. It
   depends on a package from Hex, the package registry.
3. Compile, run, test and format it.
4. Build environments (`MIX_ENV`) and configuration files.
5. Scripts that need a package, with `Mix.install/1`.

## A new project

`mix new <name>` creates a project directory. We make one in a throwaway
directory just to see what it contains, then delete it.

```sh
mix new demo
rm -rf demo
```

Every Mix project has the same layout: `mix.exs` describes the project, `lib/`
holds the code, `test/` the tests, and `.formatter.exs` tells `mix format`
which files to format. Mix generates two more directories when it runs:
`deps/` for downloaded dependencies and `_build/` for compiled code. Neither
belongs in version control, which is what the generated `.gitignore` says.

## The project

`bill` is laid out the same way. `mix.exs` is an ordinary module. `use
Mix.Project` makes it the project definition, and Mix calls its functions:

- `project/0` names the app (`:bill`), gives its version, the Elixir versions
  it works with, and its dependencies. `elixirc_options: [warnings_as_errors:
  true]` makes every compiler warning fail the build, so none slip through.
  (`mix compile --warnings-as-errors` does the same for a single run.)
- `application/0` describes the *OTP application* the project compiles to: a
  named component that is loaded, started and stopped as a unit.
  `extra_applications: [:logger]` says Elixir's `Logger` must be started
  before `bill`. [Applications and Configuration](/otp/applications) shows
  what else goes here once you have processes to start.

```file mix.exs
```

`{:decimal, "~> 3.2"}` is a dependency on the
[Decimal](https://hex.pm/packages/decimal) package from
[Hex](https://hex.pm), the package registry for Elixir and Erlang. Floats
can't represent most decimal fractions exactly (`0.1 + 0.2` is
`0.30000000000000004`), so money should never be a float. Decimal does exact
decimal arithmetic.

The string after the name is a *version requirement*. `~> 3.2` means "3.2 or
any later 3.x": updates that by convention add features without breaking
anything, but never 4.0. With a third number, `~> 3.2.0` would allow only
3.2.x bug fixes. Elixir's `Version` module does the matching, and shows
exactly what each form accepts:

```sh
elixir -e 'IO.inspect(for v <- ["3.2.0", "3.9.1", "4.0.0"], do: {v, Version.match?(v, "~> 3.2")})'
elixir -e 'IO.inspect(for v <- ["3.2.7", "3.3.0"], do: {v, Version.match?(v, "~> 3.2.0")})'
```

```file .formatter.exs
```

```file .gitignore
```

The library itself: three public functions, with exact arithmetic delegated to
Decimal. `split/2` works in whole cents so the shares always add up to the
total. `format/1` reads the currency from the configuration (below).

```file lib/bill.ex
```

Tests live in `test/` and use ExUnit, Elixir's test framework.
`test_helper.exs` runs first and starts it.

```file test/test_helper.exs
```

`use ExUnit.Case` turns the module into a test case. Each `test` is a named
block of `assert`s: an `assert` on a comparison that fails shows both sides.
`doctest Bill` also runs the `iex>` example in `Bill.total/1`'s `@doc` as a
test, so documentation examples can't go stale.

```file test/bill_test.exs
```

## Fetch dependencies and compile

`mix deps.get` downloads the dependencies into `deps/` and records the exact
versions in `mix.lock`. It prints download progress and timings, so its
output is hidden here.

```sh
mix deps.get > /dev/null
ls deps
```

`mix.lock` pins every dependency, direct or not, to one version and a
checksum of its contents. Commit it: everyone who builds the project, and
every server, then gets exactly the same code, even after Decimal publishes
3.3. `mix deps.update decimal` moves the lock forward when you choose to.

```file mix.lock
```

`mix compile` compiles the dependencies first, then the project, and writes
one `.beam` file per module (see [Compilation](/core/compilation)) into
`_build`.

```sh
mix compile
ls _build/dev/lib
ls _build/dev/lib/bill/ebin
```

Besides the module, `ebin` holds `bill.app`: the application description Mix
generated from `mix.exs`. [Applications and Configuration](/otp/applications)
looks inside it.

`mix deps.tree` shows which package needs which. Here the tree is short.

```sh
mix deps.tree
```

## Run it

`mix run -e` compiles the project if needed, starts it, and runs one
expression with all of its modules and dependencies available. (`mix run
file.exs` runs a script the same way.)

```sh
mix run -e 'IO.inspect(Bill.total(["1.10", "2.20"]))'
mix run -e 'IO.inspect(Bill.split(["10.00"], 3))'
mix run -e 'IO.puts(Bill.format(Bill.total(["1.10", "2.20"])))'
```

To try things by hand, `iex -S mix` starts IEx, Elixir's interactive shell,
inside the project: everything `mix run` loads is there, and `recompile()`
picks up the edits you make while it runs. It's interactive, so it can't run
on this page.

## Test it

`mix test` runs every `*_test.exs` file under `test/`. Tests run in a random
order to flush out tests that depend on each other; the seed is printed so a
failing order can be repeated with `--seed`. We fix the seed, pin
`--max-cases` (how many tests may run at once; the default, twice the number
of CPU cores, is printed too), and drop the line with the run time, so the
output below is the same on every machine. `mix test` builds in the `test`
environment (more below), so it compiles everything again first. Each `.` is a
passing test.

```sh
mix test --seed 0 --max-cases 1 | grep -v '^Finished in'
```

## Format it

`mix format` rewrites the files listed in `.formatter.exs` in the one standard
Elixir style. With `--check-formatted` it changes nothing and fails if any
file would change, which is what CI runs. Silence means every file is
formatted.

```sh
mix format --check-formatted
```

Given `-` it formats standard input instead, which shows what it does:

```sh
printf 'defmodule Tip do\ndef of(amount),do: amount\nend\n' | mix format -
```

`mix help` lists every task (built-in ones, those of your dependencies and
your own), and `mix help <task>` documents one. `--search` filters the list:

```sh
mix help --search deps
```

## Environments and configuration

Mix builds in one of three environments, chosen by the `MIX_ENV` variable:
`dev` (the default), `test` (which `mix test` switches to by itself) and
`prod`. Each compiles into its own directory under `_build`, which is why
there was a `_build/dev` above.

Configuration goes in `config/config.exs`. Each `config :app, key: value` sets
a key in that application's *environment*, a keyword store that belongs to
the OTP application. `import Config` makes the `config` macro available, and
the last line pulls in the file for the current environment, so it can
override what came before.

```file config/config.exs
```

```file config/dev.exs
```

```file config/test.exs
```

```file config/prod.exs
```

Code reads it with `Application.fetch_env!(:bill, :currency)`, which raises if
the key is missing, or `Application.get_env(:bill, :currency, "EUR")`, which
returns a default instead. So `Bill.format/1` says `EUR` under `mix run`, the
test above expected `XTS`, and in `prod`:

```sh
MIX_ENV=prod mix run -e 'IO.puts(Bill.format(Decimal.new("9.99")))'
ls _build
```

The `prod` build compiled everything again into `_build/prod`, and `_build`
now has one directory per environment that has run.

These files are read when the project is *built*. Settings that must be read
on the server when the program starts, such as secrets from environment
variables, go in `config/runtime.exs`, covered in
[Runtime Configuration](/deployment/runtime-config).

## Scripts with dependencies

A single script can use Hex packages too. `Mix.install/1` at the top fetches
and compiles them on the first run and caches them, so later runs start
quickly:

```elixir
Mix.install([{:decimal, "~> 3.2"}])

IO.puts(Decimal.add(Decimal.new("0.1"), Decimal.new("0.2")))
```

`Mix.install/1` prints its progress the first time but not later, so the
scripts on this site that use it first call `Mix.start()` and
`Mix.shell(Mix.Shell.Quiet)`, which silences Mix's own output, so their output
is the same every time.

> **Pitfall:** reading configuration in a module body, as in `@currency
> Application.fetch_env!(:bill, :currency)`, runs once at compile time and
> freezes the value into the compiled code. The compiler warns about it. Read
> configuration inside functions, as `Bill.format/1` does;
> [Applications and Configuration](/otp/applications) covers
> `Application.compile_env/3` for the rare value that must be fixed at compile
> time.

> **Pitfall:** `Mix.install/1` is for scripts only. Inside a Mix project it
> raises "Mix.install/2 cannot be used inside a Mix project"; add the package
> to `deps` in `mix.exs` instead.

> **Pitfall:** a version requirement without a lock file is a range, not a
> version. Without `mix.lock` in version control, two machines that run
> `mix deps.get` a week apart can build different code.
