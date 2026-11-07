defmodule Ebe.Source do
  @moduledoc """
  Splits an example `.exs` file into cells (documentation + code segments).

  The rule is deliberately simple so example files stay plain, idiomatic Elixir:

    * A comment starting at column 0 (`# text` or a bare `#`) is prose, written
      in Markdown.
    * Everything else, including indented comments and trailing `# =>` notes,
      is code.

  Consecutive prose lines followed by consecutive code lines form one segment.
  A segment may have prose without code (a paragraph that introduces the next
  idea) or code without prose.

  `program/1` joins the code cells, without the prose, into the program that
  is run at build time and in the browser. Its lines are numbered straight
  through from 1, as the page shows them, and a marker at the start of each
  cell lets a single run be split into per-cell output (the marker shares the
  cell's first line, so line numbers don't shift).
  """

  defmodule Segment do
    @moduledoc """
    A run of prose and the code it describes. `line` is the 1-based line of
    the first code line in the original file, or nil when there is no code.
    """
    @enforce_keys [:doc, :code]
    defstruct [:doc, :code, line: nil]

    @type t :: %__MODULE__{doc: String.t(), code: String.t(), line: pos_integer() | nil}
  end

  @doc_line ~r/\A#(?: |\z)/

  # ASCII "record separator" brackets the cell index. It never appears in
  # normal program output and survives every transport (port, Wasm stdout).
  @marker_char "\u001E"

  @doc """
  Parses source into segments.

      iex> Ebe.Source.segments("# Hi\\nIO.puts(1)\\n")
      [%Ebe.Source.Segment{doc: "Hi", code: "IO.puts(1)", line: 2}]
  """
  @spec segments(String.t()) :: [Segment.t()]
  def segments(source) when is_binary(source) do
    source
    |> lines()
    |> Enum.chunk_while({[], []}, &chunk/2, &flush/1)
    |> Enum.map(&finish/1)
    |> Enum.reject(&(&1.doc == "" and &1.code == ""))
  end

  @doc """
  The code cells of `segments`, one after another with no prose or blank lines
  between them, each starting with its cell marker. Cells are numbered from 1
  in the order `segments/1` returns code-bearing segments.

      iex> Ebe.Source.program(Ebe.Source.segments("# Hi\\nIO.puts(1)\\n# Bye\\nIO.puts(2)\\n"))
      ~s|IO.write("\\\\u001E1\\\\u001E"); IO.puts(1)\\nIO.write("\\\\u001E2\\\\u001E"); IO.puts(2)\\n|
  """
  @spec program([Segment.t()]) :: String.t()
  def program(segments) do
    cells =
      segments
      |> Enum.filter(& &1.line)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {seg, n} -> marker_call(n) <> seg.code end)

    cells <> "\n"
  end

  @doc "The Elixir statement that announces cell `n` on stdout."
  @spec marker_call(pos_integer()) :: String.t()
  def marker_call(n), do: ~s|IO.write("\\u001E#{n}\\u001E"); |

  @doc """
  Splits program output into `%{cell => text}` using the markers written by an
  instrumented run. Output printed before the first marker goes to cell 1.
  """
  @spec split_output(String.t()) :: %{pos_integer() => String.t()}
  def split_output(output) do
    [head | rest] = String.split(output, @marker_char)

    rest
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{1 => head}, fn
      [n, text], acc -> Map.update(acc, String.to_integer(n), text, &(&1 <> text))
      [n], acc -> Map.put_new(acc, String.to_integer(n), "")
    end)
    |> Map.new(fn {k, v} -> {k, String.trim_trailing(v, "\n")} end)
  end

  @doc "Removes cell markers, giving the output a plain run would print."
  @spec strip_markers(String.t()) :: String.t()
  def strip_markers(output), do: String.replace(output, ~r/\x{1E}\d+\x{1E}/u, "")

  defp lines(source) do
    source
    |> String.split(["\r\n", "\n"])
    |> Enum.with_index(1)
    |> case do
      [{"#!" <> _, 1} | rest] -> rest
      lines -> lines
    end
  end

  defp chunk({text, _n} = line, {doc, code} = acc) do
    cond do
      doc_line?(text) and code_has_content?(code) -> {:cont, acc, {[strip(text)], []}}
      doc_line?(text) -> {:cont, {[strip(text) | doc], code}}
      true -> {:cont, {doc, [line | code]}}
    end
  end

  defp flush(acc), do: {:cont, acc, {[], []}}

  defp finish({doc, code}) do
    # `code` was accumulated in reverse: drop trailing blanks, restore order,
    # then drop leading blanks.
    code =
      code
      |> Enum.drop_while(&blank?/1)
      |> Enum.reverse()
      |> Enum.drop_while(&blank?/1)

    %Segment{
      doc: doc |> Enum.reverse() |> Enum.join("\n") |> String.trim(),
      code: Enum.map_join(code, "\n", &elem(&1, 0)),
      line:
        case code do
          [{_, n} | _] -> n
          [] -> nil
        end
    }
  end

  defp blank?({text, _}), do: String.trim(text) == ""

  defp doc_line?(line), do: Regex.match?(@doc_line, line)

  defp code_has_content?(code), do: Enum.any?(code, &(not blank?(&1)))

  defp strip("#"), do: ""
  defp strip("# " <> text), do: text
end
