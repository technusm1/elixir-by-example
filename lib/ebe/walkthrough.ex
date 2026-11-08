defmodule Ebe.Walkthrough do
  @moduledoc """
  Multi-file examples: a directory holding a small project plus a
  `walkthrough.md` that explains it.

  The walkthrough is Markdown with two kinds of special fenced blocks:

    * ` ```file <path>``` ` (empty body) shows the project file at `<path>`,
      relative to the directory. Every project file must be shown once, so the
      page and the download never disagree.
    * ` ```sh``` ` holds shell commands. At build time they run, in order, in a
      fresh copy of the project, and their output is captured for the page.
      ` ```sh fails``` ` marks a block that must exit with a non-zero status
      (to show an error on purpose).

  Everything else is prose.

  A walkthrough registered with `guide: true` in the catalog is a *guide*: its
  `sh` blocks are shown but never run (they need Docker, a cluster, a cloud
  account), so its page shows no output and says so.
  """

  defmodule Block do
    @moduledoc "One piece of a walkthrough, in reading order."
    @enforce_keys [:kind, :text]
    defstruct [:kind, :text, path: nil, fails: false]

    @type t :: %__MODULE__{
            kind: :prose | :file | :sh,
            text: String.t(),
            path: String.t() | nil,
            fails: boolean()
          }
  end

  @walkthrough "walkthrough.md"
  # Never part of a project, even if a local run left them behind.
  @ignored ~w(_build deps .elixir_ls erl_crash.dump)

  @doc "The walkthrough file name inside a project directory."
  @spec walkthrough() :: String.t()
  def walkthrough, do: @walkthrough

  @doc """
  Parses a walkthrough.

      iex> text = "Intro\\n\\n```file mix.exs\\n```\\n\\n```sh fails\\nmix boom\\n```\\n"
      iex> Ebe.Walkthrough.parse(text) |> Enum.map(&{&1.kind, &1.path, &1.fails})
      [{:prose, nil, false}, {:file, "mix.exs", false}, {:sh, nil, true}]
  """
  @spec parse(String.t()) :: [Block.t()]
  def parse(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> chunk([], [])
    |> Enum.reject(&(&1.kind == :prose and String.trim(&1.text) == ""))
  end

  defp chunk([], prose, acc), do: Enum.reverse(flush(prose, acc))

  defp chunk(["```file " <> path | rest], prose, acc) do
    {_body, rest} = take_fence(rest, [])
    block = %Block{kind: :file, text: "", path: String.trim(path)}
    chunk(rest, [], [block | flush(prose, acc)])
  end

  defp chunk(["```sh" <> info | rest], prose, acc) do
    {body, rest} = take_fence(rest, [])
    block = %Block{kind: :sh, text: body, fails: String.trim(info) == "fails"}
    chunk(rest, [], [block | flush(prose, acc)])
  end

  defp chunk([line | rest], prose, acc), do: chunk(rest, [line | prose], acc)

  defp take_fence(["```" | rest], body), do: {body |> Enum.reverse() |> Enum.join("\n"), rest}
  defp take_fence([line | rest], body), do: take_fence(rest, [line | body])
  defp take_fence([], _body), do: raise(ArgumentError, "unclosed ``` block in walkthrough")

  defp flush([], acc), do: acc

  defp flush(prose, acc),
    do: [%Block{kind: :prose, text: prose |> Enum.reverse() |> Enum.join("\n")} | acc]

  @doc """
  The project files in `dir`, as sorted relative paths, without the
  walkthrough and without build artifacts.
  """
  @spec files(Path.t()) :: [String.t()]
  def files(dir) do
    Path.wildcard(Path.join(dir, "**/*"), match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.reject(fn rel -> rel == @walkthrough or hd(Path.split(rel)) in @ignored end)
    |> Enum.sort()
  end

  @doc """
  Checks that the walkthrough shows every project file exactly once and only
  files that exist. Returns `:ok` or `{:error, message}`.
  """
  @spec check([Block.t()], [String.t()], boolean()) :: :ok | {:error, String.t()}
  def check(blocks, files, guide? \\ false) do
    with :ok <- check_files(blocks, files), do: check_commands(blocks, guide?)
  end

  defp check_files(blocks, files) do
    shown = for %Block{kind: :file, path: path} <- blocks, do: path

    cond do
      (missing = Enum.uniq(shown) -- files) != [] ->
        {:error, "shows files that don't exist: #{inspect(missing)}"}

      (unshown = files -- shown) != [] ->
        {:error, "never shows: #{inspect(unshown)}"}

      (dupes = shown -- Enum.uniq(shown)) != [] ->
        {:error, "shows twice: #{inspect(dupes)}"}

      true ->
        :ok
    end
  end

  defp check_commands(blocks, guide?) do
    cond do
      not guide? and not Enum.any?(blocks, &(&1.kind == :sh)) ->
        {:error, "has no ```sh block"}

      guide? and Enum.any?(blocks, & &1.fails) ->
        {:error, "is a guide: nothing runs, so nothing can be marked `fails`"}

      true ->
        :ok
    end
  end

  @doc """
  The commands of a `sh` block as shown on the page: a `$` prompt before each
  command, none before comments, blank lines, continuation lines (after a
  trailing `\\`, `&&`, `||` or `|`) or the body of a compound command (`for ... do ... done`,
  `if ... then ... fi`, `case ... esac`).
  """
  @spec prompted(String.t()) :: [{:command | :continued | :comment | :blank, String.t()}]
  def prompted(script) do
    {lines, _} =
      script
      |> String.split("\n")
      |> Enum.map_reduce({false, 0}, fn line, {continued?, depth} ->
        trimmed = String.trim(line)

        kind =
          cond do
            continued? or depth > 0 -> :continued
            trimmed == "" -> :blank
            String.starts_with?(trimmed, "#") -> :comment
            true -> :command
          end

        code? = kind in [:command, :continued] and not String.starts_with?(trimmed, "#")
        depth = if code?, do: max(depth + nesting(trimmed), 0), else: depth
        {{kind, line}, {code? and continues?(trimmed), depth}}
      end)

    lines
  end

  # A trailing `\\`, `&&`, `||` or `|` carries the command onto the next line.
  defp continues?(line), do: String.ends_with?(line, ["\\", "&&", "||", "|"])

  # How much a line opens (+) or closes (-) a compound command.
  defp nesting(line) do
    words = String.split(line, ~r/[\s;]+/, trim: true)
    opens = Enum.count(words, &(&1 in ~w(do then case)))
    closes = Enum.count(words, &(&1 in ~w(done fi esac)))
    opens - closes
  end
end
