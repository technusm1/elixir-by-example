The Releases page ended with a catch: a release contains the Erlang runtime
and native code built for the machine that built it, so it must be built on
the same OS, CPU architecture and C library as the servers that run it. And
those servers still need a few system libraries the runtime links against.

A container image solves both. You build the release *inside* a Linux image
that matches production, then copy just the release into a small image with
the libraries it needs. The result runs the same on a laptop, in CI and on
any server or cluster that runs containers.

On this page:

1. The `greeter` project from the Releases page, unchanged.
2. A two-stage `Dockerfile`: one stage builds the release, the other runs it.
3. Building the image and operating the release inside a container.

## The project

The same project as on the Releases page. Nothing in it knows about
containers.

```file mix.exs
```

```file lib/greeter/application.ex
```

```file lib/greeter/counter.ex
```

## The Dockerfile

This follows the Dockerfile Phoenix generates (`mix phx.gen.release --docker`),
trimmed to what this project needs: it has no dependencies, configuration or
assets.

The first stage starts from an image with Elixir and Erlang installed and runs
`mix release`. The second starts from plain Debian, installs the few libraries
the runtime needs, and copies in only the release. The image you ship
contains no compiler, no Mix and no source code.

```file Dockerfile
```

`docker build` sends the project directory to the builder. Anything listed in
`.dockerignore` stays behind, most importantly a `_build` from your own
machine.

```file .dockerignore
```

## Build and run

```sh
docker build -t greeter .
docker run -d --rm --name greeter greeter
until docker exec greeter /app/bin/greeter pid > /dev/null 2>&1; do sleep 0.1; done
```

The release script works inside the container just as on the Releases page.
`docker exec` runs it next to the running app, so `rpc` reaches the same
counter every time.

```sh
docker exec greeter /app/bin/greeter rpc 'IO.puts(Greeter.Counter.next())'
docker exec greeter /app/bin/greeter rpc 'IO.puts(Greeter.Counter.next())'
```

`docker stop` sends the main process `SIGTERM`. The Erlang runtime treats that
as a request to shut down cleanly, the same as `bin/greeter stop`.

```sh
docker stop greeter
```

> **Pitfall:** prefer Debian or Ubuntu images to Alpine. Alpine uses a
> different C library (musl), and the Phoenix team recommends against it
> because of DNS resolution failures and trouble with dynamically linked NIFs
> and precompiled binaries.

> **Pitfall:** pin exact image tags (Elixir, OTP *and* the Debian date) and use
> the same Debian release in both stages. A floating tag means the release
> you tested is not the one you ship.

> **Pitfall:** never bake secrets into an image: anyone who can pull it can read
> them. The image stays the same everywhere; secrets arrive as environment
> variables or mounted files at `docker run` time and are read in
> `config/runtime.exs` (see Runtime Configuration).

> **Pitfall:** the release script becomes the container's main process.
> Platforms that don't reap zombie processes may need a small init such as
> `tini` as the entry point, as the Phoenix Dockerfile notes.
