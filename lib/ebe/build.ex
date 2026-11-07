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

    case Catalog.unregistered_files() do
      [] ->
        :ok

      files ->
        raise "Example files not registered in Ebe.Catalog:\n  " <> Enum.join(files, "\n  ")
    end

    Runner.check_toolchain!()

    tracks = Catalog.tracks()
    entries = Enum.flat_map(tracks, &(&1.examples ++ &1.steps))
    by_slug = for t <- tracks, e <- t.examples, into: %{}, do: {e.slug, e}

    outputs = run_all(entries)

    case for({e, {:error, msg}} <- outputs, do: {e, msg}) do
      [] ->
        :ok

      failures ->
        report = Enum.map_join(failures, "\n\n", fn {_e, msg} -> msg end)
        raise "#{length(failures)} example(s) failed:\n\n" <> report
    end

    outputs = Map.new(outputs, fn {e, {:ok, out}} -> {e.url, out} end)
    css = File.read!(Path.join(@static, "site.css")) |> minify_css()

    File.rm_rf!(out)
    File.mkdir_p!(out)

    pages =
      entries
      |> with_neighbours()
      |> Enum.map(fn {prev, entry, next} ->
        build_page(entry, prev, next, Map.fetch!(outputs, entry.url), by_slug)
      end)

    track_by_id = Map.new(tracks, &{&1.id, &1})

    for page <- pages do
      html =
        Pages.to_html(&Pages.example/1, %{
          page: page,
          track: track_by_id[page.entry.track_id],
          css: css
        })

      write(out, page.entry.url <> ".html", html)
      write(out, page.entry.url <> ".exs", page.source)
    end

    write(out, "index.html", Pages.to_html(&Pages.index/1, %{tracks: tracks, css: css}))
    write(out, "404.html", Pages.to_html(&Pages.not_found/1, %{css: css}))
    write(out, "llms.txt", llms_txt(tracks, pages))
    write(out, "llms-full.txt", llms_full_txt(tracks, pages))
    write(out, "sitemap.xml", sitemap(pages))
    write(out, "robots.txt", "User-agent: *\nAllow: /\nSitemap: #{@site}/sitemap.xml\n")

    copy_static(out)
    copy_popcorn(out)

    ms = System.monotonic_time(:millisecond) - started
    Logger.info("Built #{length(pages)} pages into #{Path.relative_to_cwd(out)} in #{ms}ms")
    :ok
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

  defp cached_run(%Entry{source_path: path}) do
    source = File.read!(path)

    key =
      :crypto.hash(:sha256, [source, System.version(), System.otp_release()])
      |> Base.url_encode64(padding: false)

    cache = Path.join(@cache_dir, key)

    case File.read(cache) do
      {:ok, output} ->
        {:ok, output}

      {:error, _} ->
        with {:ok, output} <- Runner.run(path) do
          File.write!(cache, output)
          {:ok, output}
        end
    end
  end

  ## Pages

  defp build_page(%Entry{} = entry, prev, next, output, by_slug) do
    source = File.read!(entry.source_path)
    segments = Source.segments(source)

    %Page{
      entry: entry,
      source: source,
      segments: Enum.map(segments, &render_segment/1),
      output: String.trim_trailing(output),
      description: describe(segments, entry),
      uses: Enum.map(entry.uses, &Map.fetch!(by_slug, &1)),
      edit_url: @repo_blob <> Path.relative_to(entry.source_path, @root),
      prev: prev,
      next: next
    }
  end

  defp render_segment(%Source.Segment{doc: doc, code: code}) do
    %Page.Segment{
      doc_html: if(doc == "", do: "", else: markdown(doc)),
      code_html: if(code == "", do: "", else: highlight(code))
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

  defp llms_txt(tracks, pages) do
    by_url = Map.new(pages, &{&1.entry.url, &1})

    sections =
      for %Track{} = t <- tracks do
        examples = Enum.map_join(t.examples, "\n", &llms_line(&1, by_url))
        steps = Enum.map_join(t.steps, "\n", &llms_line(&1, by_url))

        """
        ## #{t.title}

        #{t.blurb}

        #{examples}

        ### Project: #{t.project_title}

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

  defp llms_full_txt(tracks, pages) do
    by_url = Map.new(pages, &{&1.entry.url, &1})

    body =
      for t <- tracks, e <- t.examples ++ t.steps do
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

    "# Elixir by Example (full text)\n\nVerified on Elixir #{System.version()} / OTP #{System.otp_release()}.\n\n" <>
      Enum.join(body, "\n")
  end

  defp sitemap(pages) do
    urls = ["/" | Enum.map(pages, & &1.entry.url)]

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
