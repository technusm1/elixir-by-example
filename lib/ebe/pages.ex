defmodule Ebe.Pages do
  @moduledoc """
  HEEx templates for every page. Using `Phoenix.Component` gives us compile-time
  validation of the HTML structure and of component attributes (`attr`), so a
  typo in a template fails `mix compile` instead of shipping broken markup.
  """

  use Phoenix.Component

  alias Ebe.Catalog.{Entry, Track}
  alias Ebe.Page
  alias Phoenix.HTML.Safe
  alias Phoenix.LiveView.Rendered

  @repo "https://github.com/technusm1/elixir-by-example"
  @site "https://elixirbyexample.com"

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :path, :string, required: true
  attr :css, :string, required: true
  attr :tracks, :list, required: true
  attr :scripts, :list, default: []
  slot :inner_block, required: true

  def layout(assigns) do
    assigns = assign(assigns, repo: @repo, site: @site)

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <title>{@title}</title>
        <meta name="description" content={@description} />
        <link rel="canonical" href={@site <> @path} />
        <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
        <link rel="icon" href="/favicon-32.png" sizes="32x32" type="image/png" />
        <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
        <link rel="alternate" type="text/plain" title="llms.txt" href="/llms.txt" />
        <meta name="theme-color" content="#5c3b8c" />
        <meta property="og:type" content="website" />
        <meta property="og:site_name" content="Elixir by Example" />
        <meta property="og:title" content={@title} />
        <meta property="og:description" content={@description} />
        <meta property="og:url" content={@site <> @path} />
        <meta property="og:image" content={@site <> "/og.png"} />
        <meta name="twitter:card" content="summary_large_image" />
        <style>
          <%= Phoenix.HTML.raw(@css) %>
        </style>
        <script :for={src <- @scripts} src={src} type="module" defer>
        </script>
      </head>
      <body>
        <header class="site">
          <div class="site-inner">
            <a class="brand" href="/">
              <img src="/favicon.svg" alt="" width="26" height="26" />
              <span>Elixir by Example</span>
            </a>
            <nav class="tracks-nav" aria-label="Tracks">
              <a :for={t <- @tracks} href={"/##{t.id}"}>{short_title(t)}</a>
            </nav>
            <nav class="meta-nav">
              <a href="/about">About</a>
              <a href={@repo} title="Source on GitHub">GitHub</a>
            </nav>
          </div>
        </header>
        {render_slot(@inner_block)}
        <footer class="site">
          <div class="site-inner">
            <span>
              <a href="/about">About</a>
              · <a href={@repo}>source</a>
              · by <a href="https://maheepk.net">Maheep Kumar</a>
            </span>
          </div>
        </footer>
      </body>
    </html>
    """
  end

  attr :tracks, :list, required: true
  attr :css, :string, required: true

  def index(assigns) do
    ~H"""
    <.layout
      title="Elixir by Example"
      description="Learn Elixir, OTP and distributed systems through small, verified, runnable examples."
      path="/"
      css={@css}
      tracks={@tracks}
    >
      <main class="home">
        <section class="hero">
          <img src="/favicon.svg" alt="" width="72" height="72" />
          <h1>Elixir by Example</h1>
          <p class="lead">
            A hands-on tour of <a href="https://elixir-lang.org">Elixir</a>, OTP and
            distributed systems through small, annotated programs, from your first
            <code>IO.puts</code>
            to supervised, concurrent services.
          </p>
        </section>

        <section :for={track <- @tracks} class="track-card" id={track.id}>
          <header>
            <span class="track-no">{String.pad_leading("#{track.index}", 2, "0")}</span>
            <div>
              <h2>{track.title}</h2>
              <p>{track.blurb}</p>
            </div>
          </header>
          <ol class="topics">
            <li :for={e <- track.examples}><a href={e.url}>{e.title}</a></li>
          </ol>
          <div class="project">
            <h3>
              <span class="tag">Project</span>
              <a href={track.intro.url}>{track.project_title}</a>
            </h3>
            <ol class="steps">
              <li :for={s <- track.steps}><a href={s.url}>{s.title}</a></li>
            </ol>
          </div>
        </section>

        <section class="track-card soon">
          <header>
            <span class="track-no">{String.pad_leading("#{length(@tracks) + 1}", 2, "0")}</span>
            <div>
              <h2>Distributed Elixir <span class="tag">coming next</span></h2>
              <p>
                Nodes, <code>:global</code>
                and <code>:pg</code>, network partitions and Mnesia. The KV store goes multi-node.
              </p>
            </div>
          </header>
        </section>
      </main>
    </.layout>
    """
  end

  attr :page, Page, required: true
  attr :track, Track, required: true
  attr :tracks, :list, required: true
  attr :css, :string, required: true
  attr :runtime, :string, required: true, doc: "versioned path of the browser runtime"

  def example(assigns) do
    ~H"""
    <.layout
      title={"#{@page.entry.title} · Elixir by Example"}
      description={@page.description}
      path={@page.entry.url}
      css={@css}
      tracks={@tracks}
      scripts={if @page.entry.no_run, do: [], else: ["/run.js"]}
    >
      <main class="example">
        <nav class="crumbs">
          <a href={"/##{@track.id}"}>{@track.title}</a>
          <span :if={@page.entry.kind == :step}>
            › <a href={@track.intro.url}><span class="tag">Project</span> {@track.project_title}</a>
          </span>
        </nav>
        <h1>{@page.entry.title}</h1>
        <p :if={@page.uses != []} class="uses">
          Builds on <a :for={u <- @page.uses} href={u.url} class="chip">{u.title}</a>
        </p>

        <div class="notebook" data-file={@page.entry.slug <> ".exs"} data-runtime={@runtime}>
          <div class="nb-bar">
            <span class="nb-hint">
              {if @page.entry.no_run,
                do: "Runs on the native BEAM only",
                else: "Edit any cell and run it in your browser"}
            </span>
            <span class="nb-status" id="status" aria-live="polite"></span>
            <.run_controls entry={@page.entry} />
          </div>

          <section :for={seg <- @page.segments} class={["step", is_nil(seg.cell) && "prose-only"]}>
            <div :if={seg.doc_html != ""} class="prose">{Phoenix.HTML.raw(seg.doc_html)}</div>
            <div :if={seg.cell} class="cell" data-cell={seg.cell} data-line={seg.line}>
              <span class="cell-no" aria-hidden="true">{seg.cell}</span>
              <div class="cell-body">
                <button
                  :if={!@page.entry.no_run}
                  type="button"
                  class="cell-run"
                  title={
                    if seg.cell == 1,
                      do: "Run this cell in a fresh VM",
                      else:
                        "Run cells 1–#{seg.cell} in a fresh VM (later cells need the earlier ones)"
                  }
                >
                  {if seg.cell == 1, do: "▶ Run", else: "▶ Run to here"}
                </button>
                <pre class="code"><code>{Phoenix.HTML.raw(seg.code_html)}</code></pre>
                <textarea
                  :if={!@page.entry.no_run}
                  class="cell-edit"
                  spellcheck="false"
                  autocapitalize="off"
                  autocomplete="off"
                  aria-label={"Code of cell #{seg.cell}"}
                >{seg.code}</textarea>
                <pre class={["cell-out", seg.output in [nil, ""] && "empty"]}><code>{seg.output}</code></pre>
              </div>
            </div>
          </section>
          <textarea id="program" hidden>{@page.program}</textarea>
        </div>

        <.pager prev={@page.prev} next={@page.next} />
        <p class="edit-link"><a href={@page.edit_url}>Improve this page on GitHub</a></p>
      </main>
    </.layout>
    """
  end

  attr :entry, Entry, required: true

  defp run_controls(assigns) do
    ~H"""
    <button :if={@entry.no_run} type="button" class="btn" disabled title={@entry.no_run}>
      ▶ Run all
    </button>
    <button
      :if={!@entry.no_run}
      type="button"
      class="btn primary"
      id="run"
      title="Run every cell in your browser (⌘/Ctrl+Enter in a cell runs up to that cell)"
    >
      ▶ Run all
    </button>
    <button :if={!@entry.no_run} type="button" class="btn" id="reset" hidden>Reset</button>
    <.download entry={@entry} ext=".exs" />
    """
  end

  attr :entry, Entry, required: true
  attr :ext, :string, required: true

  defp download(assigns) do
    ~H"""
    <a
      class="btn"
      href={@entry.url <> @ext}
      download={Path.basename(@entry.url) <> @ext}
      title="Plain source file, for humans and agents"
    >
      Download source
    </a>
    """
  end

  attr :intro, :map, required: true
  attr :tracks, :list, required: true
  attr :css, :string, required: true

  def intro(assigns) do
    ~H"""
    <.layout
      title={"Project: #{@intro.entry.title} · Elixir by Example"}
      description={@intro.description}
      path={@intro.entry.url}
      css={@css}
      tracks={@tracks}
    >
      <main class="example intro">
        <nav class="crumbs">
          <a href={"/##{@intro.track.id}"}>{@intro.track.title}</a> › <span class="tag">Project</span>
        </nav>
        <h1>{@intro.entry.title}</h1>
        <div class="prose">{Phoenix.HTML.raw(@intro.html)}</div>

        <h2>Before you start</h2>
        <p class="uses">
          The steps build on <a :for={c <- @intro.concepts} href={c.url} class="chip">{c.title}</a>
        </p>

        <h2>Steps</h2>
        <ol class="step-cards">
          <li :for={step <- @intro.steps}>
            <a href={step.entry.url}>
              <strong>{step.entry.title}</strong>
              <span>{step.description}</span>
            </a>
          </li>
        </ol>

        <.pager prev={@intro.prev} next={@intro.next} />
        <p class="edit-link"><a href={@intro.edit_url}>Improve this page on GitHub</a></p>
      </main>
    </.layout>
    """
  end

  attr :prev, Entry, default: nil
  attr :next, Entry, default: nil

  defp pager(assigns) do
    ~H"""
    <nav class="pager">
      <a :if={@prev} href={@prev.url} rel="prev" class="prev">
        <small>Previous</small> {label(@prev)}
      </a>
      <a :if={@next} href={@next.url} rel="next" class="next">
        <small>Next</small> {label(@next)}
      </a>
    </nav>
    """
  end

  defp label(%Entry{kind: :intro, title: title}), do: "Project: " <> title
  defp label(%Entry{title: title}), do: title

  attr :css, :string, required: true
  attr :tracks, :list, required: true

  def about(assigns) do
    assigns = assign(assigns, repo: @repo)

    ~H"""
    <.layout
      title="About · Elixir by Example"
      description="What Elixir by Example is, how it works, and the open-source projects it is built on."
      path="/about"
      css={@css}
      tracks={@tracks}
    >
      <main class="example intro about">
        <h1>About</h1>
        <div class="prose">
          <p>
            Elixir by Example is a hands-on introduction to Elixir, OTP and distributed
            systems through small, annotated programs, in the spirit of <a href="https://gobyexample.com">Go by Example</a>. It is written and
            maintained by <a href="https://maheepk.net">Maheep Kumar</a>.
          </p>

          <h2>How it works</h2>
          <p>
            Every example is a plain <code>.exs</code> file. When the site is built, each one
            runs on Elixir {System.version()} / Erlang/OTP {System.otp_release()} and the
            output you see on the page is the output of that run. An example that fails,
            times out or prints a compiler warning stops the build.
          </p>
          <p>
            The Run buttons boot the Erlang virtual machine in your browser, compiled to
            WebAssembly, and run the example there. Your code never leaves your browser;
            the only thing sent is an anonymous count of runs per page (no cookies, no
            IP addresses).
            Before every deploy, each example is also run in a headless browser and its
            output compared with the native run.
          </p>
          <p>
            Spotted a mistake or want an example? <a href={@repo <> "/issues"}>Open an issue</a>
            or send a pull request; the source is MIT licensed.
          </p>

          <h2>Built on</h2>
          <p>This site exists thanks to these open-source projects and their maintainers:</p>
          <ul class="credits">
            <li>
              <a href="https://elixir-lang.org">Elixir</a>, the language, created by José Valim
              and developed by the Elixir team and community.
            </li>
            <li>
              <a href="https://www.erlang.org">Erlang/OTP</a>, the BEAM virtual machine and the
              OTP libraries, originally from Ericsson and maintained by the OTP team.
            </li>
            <li>
              <a href="https://popcorn.swmansion.com">Popcorn</a>
              by Software Mansion, which runs the BEAM in the browser via WebAssembly.
              Earlier versions were built on <a href="https://atomvm.org">AtomVM</a>,
              the lightweight BEAM implementation for microcontrollers.
            </li>
            <li>
              <a href="https://emscripten.org">Emscripten</a>
              and <a href="https://webassembly.org">WebAssembly</a>, which make that possible.
            </li>
            <li>
              <a href="https://github.com/elixir-makeup/makeup">Makeup</a>
              for syntax highlighting, the same highlighter ExDoc uses.
            </li>
            <li>
              <a href="https://github.com/leandrocp/mdex">MDEx</a>
              (built on <a href="https://github.com/kivikakk/comrak">comrak</a>) for Markdown.
            </li>
            <li>
              <a href="https://www.phoenixframework.org">Phoenix</a>
              LiveView's HEEx templates for the pages, and
              <a href="https://github.com/mtrudel/bandit">Bandit</a>
              for local previews.
            </li>
            <li>
              <a href="https://github.com/rrrene/credo">Credo</a>
              and <a href="https://github.com/jeremyjh/dialyxir">Dialyxir</a>
              for keeping the generator honest, and <a href="https://playwright.dev">Playwright</a>
              for testing every example in a real browser.
            </li>
            <li>
              <a href="https://gobyexample.com">Go by Example</a>
              by Mark McGranaghan and Eli Bendersky for the format, and
              <a href="https://livebook.dev">Livebook</a>
              for the idea of connected, runnable cells.
            </li>
          </ul>
          <p class="trademark">
            Elixir and Erlang are trademarks of their respective owners. This is an
            independent project, not affiliated with or endorsed by the Elixir team,
            the Erlang/OTP team or Software Mansion.
          </p>
        </div>
      </main>
    </.layout>
    """
  end

  attr :css, :string, required: true
  attr :tracks, :list, required: true

  def not_found(assigns) do
    ~H"""
    <.layout
      title="Not found · Elixir by Example"
      description="Page not found."
      path="/404"
      css={@css}
      tracks={@tracks}
    >
      <main class="home">
        <section class="hero">
          <h1>No page matches this path</h1>
          <pre class="cell-out"><code>** (FunctionClauseError) no function clause matching in Ebe.Router.page/1</code></pre>
          <p><a href="/">Back to all examples</a></p>
        </section>
      </main>
    </.layout>
    """
  end

  defp short_title(%Track{id: "core"}), do: "Core"
  defp short_title(%Track{id: "otp"}), do: "OTP"
  defp short_title(%Track{title: title}), do: title

  @doc "Renders a component function to an HTML string."
  @spec to_html((map() -> Rendered.t()), map()) :: String.t()
  def to_html(component, assigns) do
    assigns
    |> Map.put_new(:__changed__, nil)
    |> component.()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
