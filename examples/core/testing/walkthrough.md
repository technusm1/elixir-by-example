[Mix Projects](/core/mix) showed the basics of ExUnit, Elixir's test
framework: a test module, `test` blocks of `assert`s, doctests and `mix test`.
This page covers what a real test suite needs on top of that:

1. Grouping tests with `describe`, and the different kinds of assertion.
2. Shared setup, and the *context* each test receives.
3. What a failing test prints.
4. Which tests may run at the same time (`async`), and which may not.
5. Testing printed output and log messages.
6. Running some of the tests, and measuring how much code they run.

## The project

`span` parses and formats durations such as `1h30m`. It has no dependencies.

```file mix.exs
```

```file .formatter.exs
```

`mix test --cover` (below) writes a `cover/` directory, so it's ignored along
with the build output.

```file .gitignore
```

`parse/1` returns `{:ok, seconds}` or `{:error, reason}`, and `parse!/1` raises
instead. A configurable maximum (a week unless the `:max_seconds` key of the
application environment says otherwise) rejects durations that are too long.
The `iex>` examples in the docs run as doctests.

```file lib/span.ex
```

`Span.CLI.main/1` adds up the durations it's given and prints the total. A bad
duration is logged with `Logger.warning/1` and skipped. `require Logger` makes
Logger's macros available.

```file lib/span/cli.ex
```

## The tests

`test_helper.exs` runs before any test. `exclude: [:broken]` skips every test
tagged `:broken`; the failures section below uses that tag for tests that are
wrong on purpose.

```file test/test_helper.exs
```

`async: true` lets this module's tests run at the same time as tests from
other async modules. Within one module, tests always run one after another.

`describe` groups tests under a name, which becomes part of each test's name
(`test parse/1 adds up every unit`). Inside:

- `assert left == right` compares two values.
- `assert pattern = value` *matches* instead: it passes for any value that fits
  the pattern and binds the pattern's variables, so the next line can check
  `unit` on its own. A literal in the pattern (`5` in `{:missing_unit, 5}`)
  must match exactly.
- `refute` passes when its expression is falsy. `match?/2` returns `true` or
  `false`, so `refute match?(...)` checks a value doesn't fit a pattern.
- `assert_raise` passes only if the function raises that exception, here with
  a message matching a regular expression.

`test` is a macro, so a `for` comprehension can define a test per row of a
table. The comprehension runs at compile time, and `unquote/1` puts each row's
values into the test's body. Each test needs a unique name, so the name
includes the input.

`setup` runs before each test in its module (or, inside a `describe`, each test
of that group) and returns a map that's merged into the test's *context*. A
test receives the context as its second argument and pattern-matches what it
needs. `setup_all` is the same, but runs once per module.

```file test/span_test.exs
```

The limit test changes the application environment, which is global: every
test running at the same moment sees it. So this module is `async: false`, and
ExUnit runs it on its own, after the async modules. `on_exit/1` registers a
function that runs after the test, whether it passed or failed, and puts the
environment back.

```file test/span/limit_test.exs
```

`capture_io/1` runs a function and returns everything it printed, instead of
letting it reach the terminal. It captures the output of the test's own
process only, so it's safe in async tests. `with_log/1` returns the function's
result and the log messages sent while it ran. Logs are not per process: in an
async test they can include messages from other tests running at the same
time, so the assertion uses `=~` (does the string contain this?) rather than
`==`.

```file test/span/cli_test.exs
```

## Run the tests

As on [Mix Projects](/core/mix), the output on this page uses a fixed seed and
one test at a time, and drops the line with the run time, so it's the same on
every run. `t` wraps that up. It keeps `mix test`'s exit status, which is
non-zero when a test fails. On your machine, plain `mix test` does the same
job.

```sh
t() { s=0; mix test --seed 0 --max-cases 1 "$@" > test.log 2>&1 || s=$?; grep -v '^Finished in' test.log; return $s; }
t
```

Fifteen tests ran: three doctests and twelve tests, four of them from the `for`
comprehension. The three `:broken` tests were excluded.

## Failures

These tests are wrong on purpose. `@moduletag :broken` tags every test in the
module.

```file test/broken_test.exs
```

`--only broken` runs just the tests with that tag. It works by excluding all
tests (the `:test` tag every test has) and including `:broken` back.

```sh fails
t --only broken
```

Every failure names its test and its file and line, then shows the code, both
sides, and the stack trace:

- With `==`, `left` is what the code returned and `right` what the test
  expected.
- A failed match shows the pattern on the left and the value that didn't fit
  on the right.
- `assert_raise` reports that nothing was raised: `"1h"` is a valid duration.

## Pick the tests to run

A file name runs the tests in that file, and `file:line` runs the test at that
line. ExUnit adds a `location` filter for it, so the other tests in the file
are excluded:

```sh
t test/span_test.exs:11
```

The excluded tests are the ones in that file only; other files aren't loaded
at all. Tags select tests too: `--only tag`, `--exclude tag`, and `--include
tag` to bring back a tag that `test_helper.exs` excludes.

## Coverage

`--cover` compiles the project with Erlang's `cover` tool, which counts every
line each test runs, and prints the share of lines run per module:

```sh
t --cover
```

`cover/Elixir.Span.html` marks the one line in `Span` that no test runs:
`def parse(""), do: {:error, :empty}`. Nothing tests the empty string. High
coverage doesn't prove the tests check the right things, but a line no test
runs is certainly not checked.

> **Pitfall:** a test that changes something global isn't safe in an async
> module: the application environment, a named process or ETS table, a file,
> or the Logger level. Another test running at the same time sees the change.
> Put such tests in an `async: false` module, as `Span.LimitTest` does.

> **Pitfall:** `assert {:ok, _} = value` passes for any `{:ok, ...}`, while
> `assert value == {:ok, 5}` needs exactly that. Use a match when only the shape
> matters, and `==` when the value does.

> **Pitfall:** don't wait for something with `Process.sleep/1` in a test.
> It makes the suite slow, and still fails now and then on a busy machine.
> [Testing Processes](/otp/testing-processes) shows how to wait for messages instead.
