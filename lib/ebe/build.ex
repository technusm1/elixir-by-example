defmodule Ebe.Build do
  @moduledoc """
  Builds the static site into `dist/`.

  Pipeline: catalog → run every example on the BEAM (in parallel, cached by
  source hash and toolchain version) → render HTML → write agent-friendly
  artifacts (`llms.txt`, raw `.exs`) and Cloudflare config (`_headers`,
  `_redirects`).

  All failures are collected and reported together, and any failure aborts the
  build: a page is never published with broken code or stale output.
  """

  require Logger

  alias Ebe.Catalog
  alias Ebe.Catalog.{Entry, Track}
  alias Ebe.{Page, Pages, Runner, Source}

  @root Path.expand("../..", __DIR__)
  @static Path.join(@root, "priv/static")
  @popcorn_out Path.join(@root, "runner/out")
  @cache_dir Path.join(@root, "_build/ebe_cache")
  @repo_blob "https://github.com/technusm1/elixir-by-example/blob/main/"
  @site "https://elixirbyexample.com"

  @type opts :: [out: Path.t(), only: [String.t()] | nil]

  @doc "Builds the whole site. Raises on any failure."
  @spec run(opts()) :: :ok
  def run(opts \\ []) do
    out = Keyword.get(opts, :out, Path.join(@root, "dist"))
    started = System.monotonic_time(:millisecond)

    check_catalog!()
    Runner.check_toolchain!()

    tracks = Catalog.tracks()
    entries = Enum.flat_map(tracks, &(&1.examples ++ &1.steps))
    outputs = entries |> run_all() |> outputs!()
    {pages, intros} = build_pages(tracks, entries, outputs)

    clean!(out)
    write_site(out, tracks, pages, intros)

    ms = System.monotonic_time(:millisecond) - started
    count = length(pages) + length(intros)
    Logger.info("Built #{count} pages into #{Path.relative_to_cwd(out)} in #{ms}ms")
    :ok
  end

  # Empty `out` but keep the directory itself, so tools watching it (wrangler
  # dev, the dev server) keep working across rebuilds.
  defp clean!(out) do
    File.mkdir_p!(out)
    for entry <- File.ls!(out), do: File.rm_rf!(Path.join(out, entry))
  end

  defp check_catalog! do
    case Catalog.unregistered_files() do
      [] ->
        :ok

      files ->
        raise "Example files not registered in Ebe.Catalog:\n  " <> Enum.join(files, "\n  ")
    end
  end

  defp outputs!(results) do
    case for({e, {:error, msg}} <- results, do: {e, msg}) do
      [] ->
        Map.new(results, fn {e, {:ok, out}} -> {e.url, out} end)

      failures ->
        report = Enum.map_join(failures, "\n\n", fn {_e, msg} -> msg end)
        raise "#{length(failures)} example(s) failed:\n\n" <> report
    end
  end

  defp build_pages(tracks, entries, outputs) do
    # Reading order: a track's concept pages, its project intro, then the steps.
    ordered = Enum.flat_map(tracks, &(&1.examples ++ [&1.intro | &1.steps]))
    neighbours = Map.new(with_neighbours(ordered), fn {p, e, n} -> {e.url, {p, n}} end)
    by_slug = for t <- tracks, e <- t.examples, into: %{}, do: {e.slug, e}

    pages =
      Enum.map(entries, fn entry ->
        {prev, next} = Map.fetch!(neighbours, entry.url)
        build_page(entry, prev, next, Map.fetch!(outputs, entry.url), by_slug)
      end)

    page_by_url = Map.new(pages, &{&1.entry.url, &1})

    intros =
      for track <- tracks do
        {prev, next} = Map.fetch!(neighbours, track.intro.url)
        build_intro(track, prev, next, page_by_url)
      end

    {pages, intros}
  end

  defp write_site(out, tracks, pages, intros) do
    css = File.read!(Path.join(@static, "site.css")) |> minify_css()
    track_by_id = Map.new(tracks, &{&1.id, &1})

    for intro <- intros do
      html = Pages.to_html(&Pages.intro/1, %{intro: intro, tracks: tracks, css: css})
      write(out, intro.entry.url <> ".html", html)
      write(out, intro.entry.url <> ".md", intro.markdown)
    end

    for page <- pages do
      track = track_by_id[page.entry.track_id]
      assigns = %{page: page, track: track, tracks: tracks, css: css}
      write(out, page.entry.url <> ".html", Pages.to_html(&Pages.example/1, assigns))
      write(out, page.entry.url <> ".exs", page.source)
    end

    write(out, "index.html", Pages.to_html(&Pages.index/1, %{tracks: tracks, css: css}))
    write(out, "about.html", Pages.to_html(&Pages.about/1, %{css: css, tracks: tracks}))
    write(out, "404.html", Pages.to_html(&Pages.not_found/1, %{css: css, tracks: tracks}))
    write(out, "llms.txt", llms_txt(tracks, pages, intros))
    write(out, "llms-full.txt", llms_full_txt(tracks, pages, intros))
    write(out, "sitemap.xml", sitemap(["/about" | Enum.map(pages ++ intros, & &1.entry.url)]))
    write(out, "completions.json", Ebe.Completions.json())
    write(out, "robots.txt", "User-agent: *\nAllow: /\nSitemap: #{@site}/sitemap.xml\n")

    copy_static(out)
    copy_popcorn(out)
  end

  defp with_neighbours(entries) do
    prevs = [nil | entries]
    nexts = tl(entries) ++ [nil]
    Enum.zip([prevs, entries, nexts])
  end

  ## Running

  defp run_all(entries) do
    File.mkdir_p!(@cache_dir)

    entries
    |> Task.async_stream(&{&1, cached_run(&1)},
      max_concurrency: System.schedulers_online(),
      timeout: :infinity,
      ordered: true
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # Runs the instrumented program (cell markers added) once; the raw output,
  # markers included, is cached and later split per cell.
  defp cached_run(%Entry{source_path: path}) do
    source = path |> File.read!() |> instrumented()

    key =
      :crypto.hash(:sha256, ["v2", source, System.version(), System.otp_release()])
      |> Base.url_encode64(padding: false)

    cache = Path.join(@cache_dir, key)

    case File.read(cache) do
      {:ok, output} ->
        {:ok, output}

      {:error, _} ->
        with {:ok, output} <- Runner.run(path, source) do
          File.write!(cache, output)
          {:ok, output}
        end
    end
  end

  ## Pages

  defp instrumented(source), do: Source.instrument(source, Source.segments(source))

  defp build_page(%Entry{} = entry, prev, next, raw_output, by_slug) do
    source = File.read!(entry.source_path)
    segments = Source.segments(source)
    cell_outputs = Source.split_output(raw_output)

    {rendered, _} =
      Enum.map_reduce(segments, 1, fn
        %{line: nil} = seg, n -> {render_segment(seg, nil, nil), n}
        seg, n -> {render_segment(seg, n, Map.get(cell_outputs, n, "")), n + 1}
      end)

    %Page{
      entry: entry,
      source: source,
      program: instrumented(source),
      segments: rendered,
      output: raw_output |> Source.strip_markers() |> String.trim_trailing(),
      description: describe(segments, entry),
      uses: Enum.map(entry.uses, &Map.fetch!(by_slug, &1)),
      edit_url: @repo_blob <> Path.relative_to(entry.source_path, @root),
      prev: prev,
      next: next
    }
  end

  defp build_intro(%Track{} = track, prev, next, page_by_url) do
    entry = track.intro
    markdown = File.read!(entry.source_path)
    steps = Enum.map(track.steps, &Map.fetch!(page_by_url, &1.url))

    concepts =
      steps
      |> Enum.flat_map(& &1.uses)
      |> Enum.uniq_by(& &1.url)

    %{
      entry: entry,
      track: track,
      markdown: markdown,
      html: markdown(markdown),
      description: describe([%Source.Segment{doc: markdown, code: ""}], entry),
      steps: steps,
      concepts: concepts,
      edit_url: @repo_blob <> Path.relative_to(entry.source_path, @root),
      prev: prev,
      next: next
    }
  end

  defp render_segment(%Source.Segment{doc: doc, code: code}, cell, output) do
    %Page.Segment{
      doc_html: if(doc == "", do: "", else: markdown(doc)),
      code_html: if(code == "", do: "", else: highlight(code)),
      code: code,
      cell: cell,
      output: output
    }
  end

  @doc false
  @spec markdown(String.t()) :: String.t()
  def markdown(text) do
    MDEx.to_html!(text,
      extension: [autolink: true, strikethrough: true, table: true],
      render: [unsafe: false],
      syntax_highlight: nil
    )
  end

  @doc false
  @spec highlight(String.t()) :: String.t()
  def highlight(code), do: Makeup.highlight_inner_html(code, lexer: Makeup.Lexers.ElixirLexer)

  defp describe(segments, entry) do
    first =
      Enum.find_value(segments, "", fn
        %{doc: ""} -> nil
        %{doc: doc} -> doc
      end)

    text =
      first
      |> String.split("\n\n")
      |> hd()
      |> String.replace(~r/[`*_\[\]]|\(http[^)]*\)/, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    cond do
      text == "" -> "#{entry.title}: a runnable, annotated Elixir example."
      String.length(text) > 160 -> String.slice(text, 0, 157) <> "..."
      true -> text
    end
  end

  ## Agent-facing artifacts

  defp llms_txt(tracks, pages, intros) do
    by_url = Map.new(pages, &{&1.entry.url, &1})
    intro_by_track = Map.new(intros, &{&1.track.id, &1})

    sections =
      for %Track{} = t <- tracks do
        examples = Enum.map_join(t.examples, "\n", &llms_line(&1, by_url))
        steps = Enum.map_join(t.steps, "\n", &llms_line(&1, by_url))

        """
        ## #{t.title}

        #{t.blurb}

        #{examples}

        ### Project: #{t.project_title}

        - [About this project](#{@site}#{t.intro.url}.md): #{intro_by_track[t.id].description}
        #{steps}
        """
      end

    """
    # Elixir by Example

    > Small, annotated Elixir programs, each executed on Elixir #{System.version()} / OTP #{System.otp_release()} when the site is built, so code and output are verified. Every page has a plain-source twin: append `.exs` to its URL. The whole site as one file: #{@site}/llms-full.txt

    Conventions: column-0 `#` comments are explanations; everything else is runnable code. Notes starting with "Pitfall" describe mistakes people and coding agents commonly make.

    #{Enum.join(sections, "\n")}
    """
  end

  defp llms_line(entry, by_url) do
    page = Map.fetch!(by_url, entry.url)
    "- [#{entry.title}](#{@site}#{entry.url}.exs): #{page.description}"
  end

  defp llms_full_txt(tracks, pages, intros) do
    by_url = Map.new(pages, &{&1.entry.url, &1})
    intro_by_track = Map.new(intros, &{&1.track.id, &1})

    body =
      for t <- tracks, e <- t.examples ++ [t.intro | t.steps] do
        llms_full_entry(t, e, by_url, intro_by_track)
      end

    "# Elixir by Example (full text)\n\nVerified on Elixir #{System.version()} / OTP #{System.otp_release()}.\n\n" <>
      Enum.join(body, "\n")
  end

  defp llms_full_entry(t, %Entry{kind: :intro} = e, _by_url, intro_by_track) do
    """
    ## #{t.title}: Project: #{e.title}

    Source: #{@site}#{e.url}.md

    #{String.trim(intro_by_track[t.id].markdown)}
    """
  end

  defp llms_full_entry(t, e, by_url, _intro_by_track) do
    page = Map.fetch!(by_url, e.url)

    """
    ## #{t.title}: #{e.title}

    Source: #{@site}#{e.url}.exs

    ```elixir
    #{String.trim_trailing(page.source)}
    ```

    Output:

    ```
    #{page.output}
    ```
    """
  end

  defp sitemap(paths) do
    urls = ["/" | paths]

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(urls, "\n", &"  <url><loc>#{@site}#{&1}</loc></url>")}
    </urlset>
    """
  end

  ## Files

  defp copy_static(out) do
    for path <- Path.wildcard(Path.join(@static, "**/*"), match_dot: true),
        File.regular?(path),
        Path.basename(path) != "site.css" do
      dest = Path.join(out, Path.relative_to(path, @static))
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(path, dest)
    end
  end

  defp copy_popcorn(out) do
    if File.dir?(@popcorn_out) do
      # Brotli variants are served by the Worker; gzip variants are never used.
      for path <- Path.wildcard(Path.join(@popcorn_out, "**/*")),
          File.regular?(path),
          Path.extname(path) != ".gz" do
        dest = Path.join([out, "popcorn", Path.relative_to(path, @popcorn_out)])
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
      end
    else
      Logger.warning(
        "runner/out missing: Run buttons won't work. Build it with `mix ebe.runner`."
      )
    end
  end

  defp write(out, rel, content) do
    path = Path.join(out, String.trim_leading(rel, "/"))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  defp minify_css(css) do
    css
    |> String.replace(~r{/\*.*?\*/}s, "")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\s*([{}:;,>])\s*/, "\\1")
    |> String.replace(";}", "}")
    |> String.trim()
  end
end
