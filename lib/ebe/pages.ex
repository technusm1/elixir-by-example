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

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :path, :string, required: true
  attr :css, :string, required: true
  attr :scripts, :list, default: []
  slot :inner_block, required: true

  def layout(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <title>{@title}</title>
        <meta name="description" content={@description} />
        <link rel="canonical" href={"https://elixirbyexample.com" <> @path} />
        <link rel="icon" href="/favicon.png" />
        <link rel="alternate" type="text/plain" title="llms.txt" href="/llms.txt" />
        <style>
          <%= Phoenix.HTML.raw(@css) %>
        </style>
        <script :for={src <- @scripts} src={src} type="module" defer>
        </script>
      </head>
      <body>
        {render_slot(@inner_block)}
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
    >
      <main class="index">
        <h1>Elixir by Example</h1>
        <p>
          <a href="https://elixir-lang.org">Elixir</a>
          is a functional language on the Erlang VM, built for systems that stay up.
          This site is a hands-on introduction through small, annotated programs.
          Every example is executed on Elixir {System.version()} / OTP {System.otp_release()} when the site is built, so the code and output you see are real.
        </p>
        <p>
          Each track has reference pages for single concepts and a running project
          that puts them together. Most examples run in your browser too.
        </p>
        <section :for={track <- @tracks} class="track">
          <h2 id={track.id}>{track.title}</h2>
          <p class="blurb">{track.blurb}</p>
          <ul>
            <li :for={e <- track.examples}><a href={e.url}>{e.title}</a></li>
          </ul>
          <h3>Project: {track.project_title}</h3>
          <ol class="steps">
            <li :for={s <- track.steps}><a href={s.url}>{s.title}</a></li>
          </ol>
        </section>
        <.footer />
      </main>
    </.layout>
    """
  end

  attr :page, Page, required: true
  attr :track, Track, required: true
  attr :css, :string, required: true

  def example(assigns) do
    ~H"""
    <.layout
      title={"#{@page.entry.title} · Elixir by Example"}
      description={@page.description}
      path={@page.entry.url}
      css={@css}
      scripts={if @page.entry.no_run, do: [], else: ["/run.js"]}
    >
      <main class="example">
        <nav class="crumbs">
          <a href="/">Elixir by Example</a> / <a href={"/##{@track.id}"}>{@track.title}</a>
          <span :if={@page.entry.kind == :step}>/ Project: {@track.project_title}</span>
        </nav>
        <h1>{@page.entry.title}</h1>
        <p :if={@page.entry.uses != []} class="uses">
          Builds on: <a :for={u <- @page.uses} href={u.url}>{u.title}</a>
        </p>
        <table class="segments">
          <tr :for={seg <- @page.segments}>
            <td class="doc">{Phoenix.HTML.raw(seg.doc_html)}</td>
            <td class={["code", seg.code_html == "" && "empty"]}>
              <pre :if={seg.code_html != ""}><code>{Phoenix.HTML.raw(seg.code_html)}</code></pre>
            </td>
          </tr>
        </table>
        <section class="run">
          <div class="toolbar">
            <span class="cmd">$ elixir {@page.entry.slug}.exs</span>
            <.run_button entry={@page.entry} />
            <a
              class="raw"
              href={@page.entry.url <> ".exs"}
              title="Plain source, for humans and agents"
            >
              .exs
            </a>
          </div>
          <textarea id="source" spellcheck="false" hidden>{@page.source}</textarea>
          <pre class="output" id="output"><code>{@page.output}</code></pre>
        </section>
        <nav class="pager">
          <a :if={@page.prev} href={@page.prev.url} rel="prev">← {@page.prev.title}</a>
          <a :if={@page.next} href={@page.next.url} rel="next">{@page.next.title} →</a>
        </nav>
        <.footer edit={@page.edit_url} />
      </main>
    </.layout>
    """
  end

  attr :entry, Entry, required: true

  defp run_button(assigns) do
    ~H"""
    <button :if={@entry.no_run} type="button" class="runbtn" disabled title={@entry.no_run}>
      Run
    </button>
    <button
      :if={!@entry.no_run}
      type="button"
      class="runbtn"
      id="run"
      title="Run this example in your browser (loads the BEAM compiled to WebAssembly)"
    >
      Run
    </button>
    <button :if={!@entry.no_run} type="button" class="runbtn ghost" id="edit">Edit</button>
    """
  end

  attr :edit, :string, default: nil

  defp footer(assigns) do
    assigns = assign(assigns, :repo, @repo)

    ~H"""
    <footer>
      <a href="/llms.txt">llms.txt</a>
      · <a href={@repo}>source</a>
      <span :if={@edit}>· <a href={@edit}>edit this page</a></span>
      · by <a href="https://maheepk.net">Maheep Kumar</a>
    </footer>
    """
  end

  attr :css, :string, required: true

  def not_found(assigns) do
    ~H"""
    <.layout
      title="Not found · Elixir by Example"
      description="Page not found."
      path="/404"
      css={@css}
    >
      <main class="index">
        <h1>** (FunctionClauseError) no page matches this path</h1>
        <p><a href="/">Back to all examples</a></p>
      </main>
    </.layout>
    """
  end

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
