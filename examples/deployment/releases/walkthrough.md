So far every program ran with `elixir file.exs`, or with `mix run` inside a
Mix project (see [Mix Projects](/core/mix)). That needs Elixir, Mix and your
source code on the machine, compiles on start, and gives you no standard way
to start the app in the background, connect to it, or stop it. Servers want
something else: one directory that holds the compiled app, its dependencies
and the Erlang runtime, plus a script to operate it. That directory is a
*release*, and `mix release` builds it.

On this page:

1. A tiny Mix project, `greeter`: an application that starts a counter.
2. Build a release of it and look inside.
3. Operate it with the release's script: run a one-off command, start it in
   the background, call into the running app, and stop it.

## The project

An ordinary Mix project (see [Mix Projects](/core/mix)) whose application
starts a supervision tree (see
[Applications and Configuration](/otp/applications)). Nothing in it is
specific to releases: `mix release` works with any application.

```file mix.exs
```

The application starts one process, a counter, under a supervisor. The bare
module name in the children list means `{Greeter.Counter, []}`.

```file lib/greeter/application.ex
```

```file lib/greeter/counter.ex
```

## Build the release

`MIX_ENV=prod` builds in the `prod` environment, into `_build/prod` (see
[Mix Projects](/core/mix)). Releases are almost always built that way.

```sh
MIX_ENV=prod mix release
```

The release lands in `_build/prod/rel/greeter`. `bin` holds the script you
operate it with, `lib` the compiled code of the app and of every application it
needs (Elixir's own included), `releases` the boot files and configuration, and
`erts-*` the Erlang runtime itself. The server needs none of Elixir, Mix or the
source.

```sh
ls _build/prod/rel/greeter
ls _build/prod/rel/greeter/lib
```

## Operate it

`eval` runs one expression with the release's code loaded but the application
*not* started: handy for database migrations and other one-off tasks.

```sh
_build/prod/rel/greeter/bin/greeter eval 'IO.inspect(Code.ensure_loaded?(Greeter.Counter))'
_build/prod/rel/greeter/bin/greeter eval 'IO.inspect(Process.whereis(Greeter.Counter))'
```

`daemon` starts the app in the background (`start` keeps it in the foreground,
which is what you want under systemd or in a container). `pid` succeeds once
the node is up, so we wait for it.

```sh
_build/prod/rel/greeter/bin/greeter daemon
until _build/prod/rel/greeter/bin/greeter pid > /dev/null 2>&1; do sleep 0.1; done
```

`rpc` runs an expression *inside the running app*, over Erlang distribution.
Every call reaches the same counter, so the count keeps going up.

```sh
for i in 1 2 3; do
  _build/prod/rel/greeter/bin/greeter rpc 'IO.puts(Greeter.Counter.next())'
done
```

`stop` shuts the app down cleanly: supervisors stop their children in order,
then the VM exits.

```sh
_build/prod/rel/greeter/bin/greeter stop
```

> **Pitfall:** a release contains the Erlang runtime and native code compiled
> for the machine that built it. A release built on a Mac won't run on Linux.
> Build on the same OS, CPU architecture and libc as the servers, which is the
> main reason to build inside a container.

> **Pitfall:** `rpc` and `remote` connect with the cookie in
> `releases/COOKIE`, generated when the release is built. Every node of a
> cluster needs the same cookie: set `RELEASE_COOKIE` in the environment
> rather than relying on that file.

> **Pitfall:** `bin/greeter remote` opens an IEx shell inside the running app.
> It's the most powerful debugging tool you have and just as dangerous: any
> function you call runs in production.
