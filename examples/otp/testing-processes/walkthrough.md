[Testing with ExUnit](/core/testing) tested plain functions: call, compare,
done. A process is harder to test. It has to be started and stopped, it
answers with messages that arrive later, it may run on a timer, and a process
with a name is shared by every test. This page tests a small GenServer and
the application around it:

1. A fresh process for each test with `start_supervised!/1`.
2. Checking messages a process sends, without sleeping.
3. Driving a timer by sending its message yourself.
4. Testing a crash.
5. Testing the processes the application starts by name.

## The project

`quota` has one GenServer, `Quota.Meter`. It counts hits per key, forgets the
counts every `interval` milliseconds, and tells a `notify` process when a key
goes over its `limit`.

```file mix.exs
```

```file .formatter.exs
```

Everything the meter needs comes in as options, including the interval and
the process to notify. That's what makes it testable: a test can pick a short
limit, a reset that never fires on its own, and itself as the process to
notify. `Keyword.pop/2` takes the optional `name` out of the options, and the
meter is registered under it only if there is one. `GenServer.server()` and
`GenServer.on_start()` are types GenServer defines for "a pid or a name" and
"what `start_link` returns".

The notification is sent *before* `hit/2` replies. When `hit/2` returns, the
message is already in the notified process's mailbox.

```file lib/quota/meter.ex
```

The application starts one meter, registered as `Quota.Meter`, with a limit of
100 hits per minute.

```file lib/quota/application.ex
```

## A process per test

`mix test` starts the application before any test runs, so the named meter is
already up. The tests of the meter itself don't use it: each test starts its
own, so no test sees another's counts.

`start_supervised!/1` takes a child spec, as a supervisor's children list
does (see [Supervisors](/otp/supervisors)), and starts the process under a
supervisor that ExUnit runs for each test. It returns the pid, and stops the
process when the test ends, passed or failed, before the next test starts.
A process started with `start_link` in the test is linked to it and dies when
the test ends too, but *asynchronously*: it may still be running, holding its
name or its files, when the next test starts.

The supervised process isn't linked to the test, so its crash doesn't fail
the test by itself, and the test supervisor restarts it like any supervisor
would. `start_link_supervised!/1` links it as well, for tests where any crash
should fail the test.

These meters have no name, so the module can be `async: true`: tests running
at the same time each talk to their own meter by pid.

```file test/test_helper.exs
```

```file test/quota/meter_test.exs
```

Messages, in order of the tests:

- **Already sent.** The meter notifies before it replies, so after `hit/2`
  returns, the message is either in the test's mailbox or was never sent.
  `assert_received` checks the mailbox *now*, without waiting, and
  `refute_received` checks that no matching message is there.
  `assert_received` removes the message it matches, so the last
  `refute_received` proves the notification came only once.
- **The timer.** The reset is an ordinary `:reset` message the meter sends
  itself with `Process.send_after/3`. The test sends `:reset` itself instead
  of waiting a minute. Messages from one process to another arrive in the
  order they were sent, so the meter handles `:reset` before the `count/2`
  call that follows it.
- **Arriving later.** A process's `:DOWN` message comes from the runtime when
  the process dies, at some point after the call fails. `assert_receive`
  *waits* for a matching message, 100 ms by default (a second argument
  changes it), and fails if none comes. `^ref` and `^meter` pin the values
  already bound, so only this meter's `:DOWN` matches.

The crash test calls the meter with a message it has no clause for, so
`handle_call/3` raises and the meter dies. A process that dies makes its
callers' `GenServer.call/3` exit too, and `catch_exit/1` turns that exit into
a value the test can match. The reason is the raw Erlang error,
`{:function_clause, stacktrace}`, not an exception struct. The dying GenServer
logs an error report, with pids in it. `@tag :capture_log` captures the logs
of that one test and prints them only if it fails.

## The named process

A test of the meter the application started has to share it with every
other test that might touch `Quota.Meter`. This module is `async: false`, and
its `setup` resets the meter first, so earlier hits don't leak in.

The second test shows the other half of the problem: a meter started by a
test can't take a name that's already taken. `start_supervised/1` (no `!`)
returns the error instead of raising.

```file test/quota/application_test.exs
```

## Run them

The same `t` helper as on [Testing with ExUnit](/core/testing): a fixed seed,
one test at a time, and no run-time line.

```sh
t() { s=0; mix test --seed 0 --max-cases 1 "$@" > test.log 2>&1 || s=$?; grep -v '^Finished in' test.log; return $s; }
t
```

## A message that never comes

When `assert_receive` gives up, it shows what *is* in the mailbox. This test
waits for a notification about the wrong key:

```file test/broken_test.exs
```

```sh fails
t --only broken
```

When the message did arrive but with a different shape than the pattern, the
listing shows the difference at once.

> **Pitfall:** a test that `Process.sleep/1`s until something has happened is
> slow and still fails sometimes on a busy machine. Wait for a message with
> `assert_receive`, or make a call to the process: it handles the call after
> every message the caller sent it before, so the reply means those have all
> been handled.

> **Pitfall:** `refute_receive` waits its full timeout (100 ms by default)
> before passing, on every run. When the message would already be in the
> mailbox, as with the meter's notification, `refute_received` checks at once.

> **Pitfall:** a process registered under a fixed name can't be started once
> per test, and async tests would share it. Make the name an option, as the
> meter does, and let tests start unnamed processes.
