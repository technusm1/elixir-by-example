# Elixir by Example

Source for [elixirbyexample.com](https://elixirbyexample.com): small, annotated Elixir programs in the spirit of [Go by Example](https://gobyexample.com).

- **Verified.** Every example is a real `.exs` file, executed on the pinned Elixir/OTP when the site builds. The output on each page is captured from that run. Any failure, timeout or warning (including Elixir 1.20 type-checker warnings) fails the build.
- **Runnable in the browser.** The Run button boots the real BEAM compiled to WebAssembly ([Popcorn](https://popcorn.swmansion.com)) and runs the example there. CI checks the browser output matches the native output.
- **Agent friendly.** Every page has a plain-source twin (`/core/maps.exs`), plus [`/llms.txt`](https://elixirbyexample.com/llms.txt) and [`/llms-full.txt`](https://elixirbyexample.com/llms-full.txt).
- **Project driven.** Each track has standalone concept pages plus a running project (a key-value store that grows from a map to a supervised, ETS-backed, expiring store, and later a distributed one).

## Develop

```sh
asdf install                 # Erlang, Elixir, Node from .tool-versions
mix deps.get && npm install
mix ebe.runner               # build the in-browser runtime (once, or after toolchain/Popcorn changes)
mix ebe.server               # http://localhost:4000, rebuilds on changes
```

Full production preview (Worker, headers, local analytics DB):

```sh
mix ebe.build
npx wrangler d1 migrations apply ebe-analytics --local
npx wrangler dev             # http://localhost:8787
npm run verify:browser       # run every example in headless Chromium
```

Before pushing: `mix check` (format, warnings-as-errors, credo, dialyzer, tests, build).

## Writing an example

1. Create `examples/<track>/<slug>.exs`. Column-0 `# ` comments are Markdown prose shown next to the code that follows. Everything else, including indented comments, is code.
2. End with `# > **Pitfall:** ...` notes for mistakes people and coding agents commonly make.
3. Register it in `lib/ebe/catalog.ex`. A missing file or unknown slug is a compile error.

Pages about whole projects (releases, deployment) are directories instead: `examples/<track>/<slug>/` with the project's real files and a `walkthrough.md` whose ` ```file <path>``` ` blocks show files and whose ` ```sh``` ` blocks run at build time in one shell session. See `Ebe.Walkthrough`.
4. If it can't run in a browser (distribution, sockets, OS processes), add `no_run: "reason"`. The reason becomes the disabled Run button's tooltip.

Output must be deterministic: no pids, refs or timings in output, no races.

## Layout

```
examples/<track>/*.exs   concept pages (or <slug>/ walkthrough directories)
projects/<name>/*.exs    project steps (or <slug>/ walkthrough directories)
lib/ebe/                 generator: catalog, parser, runner, HEEx pages, build
runner/                  Popcorn app evaluating code in the browser
priv/static/             site.css (inlined), run.js, copy.js, icons (tools/icon/make_icons.swift)
worker/                  Cloudflare Worker: headers, redirects, Brotli runtime, analytics (D1)
tools/                   browser verification, analytics report
```
