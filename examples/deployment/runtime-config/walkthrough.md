A release is built once and then started on many machines: staging and
production, three regions, a laptop. Each needs its own settings (database
address, port, secrets), and secrets must never be baked into the build. But
`config/config.exs` (see [Mix Projects](/core/mix)) is evaluated when the
release is *built*: whatever it reads, it reads on the build machine, and the
value is frozen into the release.

`config/runtime.exs` is the answer: it's evaluated every time the release
*starts*, on the machine it starts on, so it can read that machine's
environment variables.

On this page:

1. Both files read `REGION`. We build the release with `REGION=build-box` and
   start it with `REGION=eu-west`: `config.exs` still says `build-box`,
   `runtime.exs` says `eu-west`.
2. `runtime.exs` requires `API_KEY`. Started without it, the release refuses
   to boot and says why.
3. A value read with `Application.compile_env/2` is frozen into the compiled
   code (see [Applications and Configuration](/otp/applications)). Changing it
   at runtime is caught at boot.

## The project

```file mix.exs
```

```file config/config.exs
```

```file config/runtime.exs
```

`Settings.report/0` prints what each file set; `Settings.greeting/0` returns a
value fixed at compile time.

```file lib/settings.ex
```

## Build on one machine, start on another

The build sees `REGION=build-box`. Note the line saying the release will use
`config/runtime.exs` at runtime.

```sh
REGION=build-box MIX_ENV=prod mix release
```

Started with `REGION=eu-west`, the two files disagree: one value was decided at
build time, the other just now.

```sh
REGION=eu-west API_KEY=k-123 _build/prod/rel/settings/bin/settings eval 'Settings.report()'
```

## A missing secret stops the boot

Without `API_KEY`, `System.fetch_env!/1` raises while the configuration is
being read, and the release stops before any of the app runs. A loud, immediate
failure beats an app that boots and fails on its first request.

```sh fails
REGION=eu-west _build/prod/rel/settings/bin/settings eval 'IO.puts(:booted)'
```

## Compile-time values can't change at runtime

`@greeting` was set from `compile_env` during the build. Setting `GREETING`
makes `runtime.exs` change that key, so the running app would disagree with
its own compiled code. The release checks for this at boot and refuses.

```sh fails
API_KEY=k-123 GREETING=hi _build/prod/rel/settings/bin/settings eval 'IO.puts(Settings.greeting())'
```

> **Pitfall:** anything `config.exs` (or `prod.exs`) reads from the
> environment comes from the *build* machine. Read environment variables only
> in `runtime.exs`, and keep secrets out of the files evaluated at build time.

> **Pitfall:** use `Application.compile_env/2` only for values that really must
> be known at compile time (they change the generated code). For everything
> else call `Application.fetch_env!/2` when you need the value.

> **Pitfall:** environment variables are inherited by every program your
> release starts and are easy to leak through logs or debug output. For real
> secrets, mount files from your platform's secret store and read those in
> `runtime.exs`.
