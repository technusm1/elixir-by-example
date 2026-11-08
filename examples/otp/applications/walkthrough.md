On the earlier pages a script started its supervisors and processes by hand,
line by line. A real system wants that done for it: when it boots, its
supervision tree should start, after everything it depends on, and when it
shuts down, the tree should stop in order. OTP's unit for this is the
*application*: a component with a name, a version, a list of applications it
needs, configuration, and optionally a supervision tree that starts and stops
with it. Elixir itself, `Logger` and every Hex package are applications, and so
is every Mix project ([Mix Projects](/core/mix) built one with no processes).

On this page:

1. `tally`, an application that counts hits per page name. Its supervision
   tree holds a `Registry`, a `DynamicSupervisor` with one counter per page,
   and a `GenServer` for the grand total.
2. How Mix starts it, and its dependencies first.
3. The application environment: configuration read when the app boots, and
   `Application.compile_env/3` for values fixed when it's compiled.
4. Child specifications: a bare module name, and a map for modules without
   `child_spec/1`.

## The project

`application/0` in `mix.exs` describes the application. `mod:` names the
*callback module* that starts it, and the list after it is passed to that
module's `start/2`. `extra_applications` lists applications that ship with
Elixir or Erlang and must be started first; applications from `deps` are added
automatically.

```file mix.exs
```

Both settings go into the application environment (see
[Mix Projects](/core/mix) for config files).

```file config/config.exs
```

`use Application` makes this a callback module. `start/2` must start the
application's top supervisor and return `{:ok, pid}`; when that supervisor
exits, the application has stopped. The first argument is the start type
(`:normal` except in distributed takeovers) and the second the list from
`mod:`. An optional `stop/1` runs after the tree has shut down, for cleanup
outside it.

`start/2` runs when the app boots, so it's the place to read the configuration
it needs: here the most counters the `DynamicSupervisor` may hold
(`max_children:`). `Tally.Total` stands alone in the list: a bare module name
means `{Tally.Total, []}`.

```file lib/tally/application.ex
```

One counter per page name, registered in `Tally.Names` under that name.

```file lib/tally/counter.ex
```

```file lib/tally/total.ex
```

`Tally.hit/1` finds the page's counter, starting it under the
`DynamicSupervisor` the first time. The guard needs the longest allowed name
as a constant, so `@max_name_length` reads it with
`Application.compile_env/3`: once, while the module is compiled.

```file lib/tally.ex
```

```file .formatter.exs
```

## The application file

`mix compile` writes `tally.app` next to the compiled modules. It's the
application's description in Erlang terms, generated from `mix.exs`, and it's
what OTP reads to load and start the app. `:file.consult/1` reads it back as
Elixir data:

```sh
mix compile
mix run -e '{:ok, [app]} = :file.consult("_build/dev/lib/tally/ebin/tally.app"); IO.inspect(app)'
```

`applications` is what must be running first: Erlang's `kernel` and `stdlib`
are always there, then `elixir`, then `logger` from `extra_applications`.
`mod` is the callback module. `compile_env` records every value the code read
at compile time, so it can be checked later (below).

## Starting it

`mix run` (and `iex -S mix`) compiles the project, then starts its application
and, before it, every application it needs, in order. `Application.spec/2`
reads a key of the description; `Application.started_applications/0` lists
what's running, most recently started first. `mix` and `compiler` are there
because Mix itself is running.

```sh
mix run -e 'IO.inspect(Application.spec(:tally, :applications))'
mix run -e 'IO.inspect(for {app, _description, _vsn} <- Application.started_applications(), do: app)'
```

The supervision tree is up before the expression runs. `which_children/1`
lists the top supervisor's children, most recently started first; the pids are
left out because they differ on every run. A `Registry` is itself a small
supervisor, hence its type.

```sh
mix run -e 'for {id, _pid, type, modules} <- Supervisor.which_children(Tally.Supervisor), do: IO.inspect({id, type, modules})'
```

Every counter is a child of `Tally.Counters`. With `max_counters: 2` a third
page is refused, and the guard rejects names longer than 10 bytes. (Each
`mix run` boots a fresh system, so nothing carries over between commands.
A list of two-element tuples that start with atoms prints as a keyword list.)

```sh
mix run -e 'IO.inspect(for page <- ["home", "home", "about", "blog"], do: Tally.hit(page)); IO.inspect(Tally.Total.get(), label: "total")'
mix run -e 'IO.inspect(Tally.hit("a-very-long-name"))'
```

`mix run --no-start` loads the code and the configuration but doesn't start
the project's application, which is useful for one-off tasks that must not
boot it.
`Application.ensure_all_started/1` then starts an application and everything
it needs, and returns the ones it had to start: only `tally`, since Mix had
already started `logger`.

```sh
mix run --no-start -e 'IO.inspect(Process.whereis(Tally.Supervisor))'
mix run --no-start -e 'IO.inspect(Application.ensure_all_started(:tally)); IO.inspect(Tally.hit("home"))'
```

## The application environment

Each application has its own environment, a keyword store filled from its
`.app` file and then from the config files. `Application.fetch_env!/2` raises
if a key is missing; `Application.get_env/3` returns a default instead.

```sh
mix run -e 'IO.inspect(Application.fetch_env!(:tally, :max_counters))'
mix run -e 'IO.inspect(Application.get_env(:tally, :missing, :default))'
```

`Application.put_env/3` changes a value while the system runs. Only code that
reads the value afterwards sees the change: `start/2` read `max_counters` when
the app booted. So before booting, with `--no-start`, the new limit takes
effect:

```sh
mix run --no-start -e 'Application.put_env(:tally, :max_counters, 3); Application.ensure_all_started(:tally); IO.inspect(for page <- ["a", "b", "c", "d"], do: Tally.hit(page))'
```

A value read with `Application.compile_env/3` is part of the compiled code, so
changing it at runtime changes nothing:

```sh
mix run -e 'Application.put_env(:tally, :max_name_length, 50); IO.inspect(Tally.hit("a-very-long-name"))'
```

That's why the `.app` file records it. When a config file changes, Mix
recompiles the project, so the new value gets compiled in. A release can't
recompile, so it checks the recorded values when it boots and refuses to start
if one changed.
[Runtime Configuration](/deployment/runtime-config) shows that, and
`config/runtime.exs`, which is read on the server each time the system starts.

Use `Application.fetch_env!/2` inside functions for almost everything, and
`compile_env` only where the compiler needs the value, as in a guard or a
module attribute.

## Child specifications

A supervisor needs a *child specification* for each child: a map that says at
least how to start it (`start: {module, function, args}`) and under which
`id`. `{Registry, keys: :unique, name: Tally.Names}` asks the module for its
spec by calling `Registry.child_spec(keys: :unique, name: Tally.Names)`, and
`use GenServer` defines a `child_spec/1` for `Tally.Total`. A bare module name
passes `[]`, so both of these are the same spec:

```sh
mix run -e 'IO.inspect(Tally.Total.child_spec([]))'
mix run -e 'IO.inspect(Supervisor.child_spec(Tally.Total, []))'
```

Erlang modules usually have no `child_spec/1`, so they go in the children list
as a map. Erlang's process groups, [`:pg`](/distributed/pg), are started like
this in later chapters:

```elixir
children = [
  %{id: :pg, start: {:pg, :start_link, []}}
]
```

> **Pitfall:** listing such a module bare, as `children = [:pg]`, fails when
> the supervisor starts: "The module :pg was given as a child to a supervisor
> but it does not implement child_spec/1". Write the map instead.

> **Pitfall:** without `mod:` in `application/0` the application still loads
> and "starts", but nothing calls `start/2`, so none of its processes run.
> That's right for a library like Decimal, and a puzzling bug when you forgot
> it.

> **Pitfall:** the application environment is global to the whole system.
> `Application.put_env/3` in one test changes it for every other test running
> at the same time. Pass settings as arguments where you can, and read the
> environment at the edges, as `start/2` does.
