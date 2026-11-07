defmodule Ebe.Source do
  @moduledoc """
  Splits an example `.exs` file into documentation/code segments.

  The rule is deliberately simple so example files stay plain, idiomatic Elixir:

    * A comment starting at column 0 (`# text` or a bare `#`) is prose, written
      in Markdown.
    * Everything else, including indented comments and trailing `# =>` notes,
      is code.

  Consecutive prose lines followed by consecutive code lines form one segment,
  rendered side by side. A segment may have prose without code (a paragraph
  that introduces the next idea) or code without prose.
  """

  defmodule Segment do
    @moduledoc "A run of prose and the code it describes."
    @enforce_keys [:doc, :code]
    defstruct [:doc, :code]

    @type t :: %__MODULE__{doc: String.t(), code: String.t()}
  end

  @doc_line ~r/\A#(?: |\z)/

  @doc """
  Parses source into segments.

      iex> Ebe.Source.segments("# Hi\\nIO.puts(1)\\n")
      [%Ebe.Source.Segment{doc: "Hi", code: "IO.puts(1)"}]
  """
  @spec segments(String.t()) :: [Segment.t()]
  def segments(source) when is_binary(source) do
    source
    |> String.split(["\r\n", "\n"])
    |> drop_shebang()
    |> Enum.chunk_while({[], []}, &chunk/2, &flush/1)
    |> Enum.map(&finish/1)
    |> Enum.reject(&(&1.doc == "" and &1.code == ""))
  end

  defp drop_shebang(["#!" <> _ | rest]), do: rest
  defp drop_shebang(lines), do: lines

  defp chunk(line, {doc, code} = acc) do
    cond do
      doc_line?(line) and code_has_content?(code) ->
        {:cont, acc, {[strip(line)], []}}

      doc_line?(line) ->
        {:cont, {[strip(line) | doc], code}}

      true ->
        {:cont, {doc, [line | code]}}
    end
  end

  defp flush(acc), do: {:cont, acc, {[], []}}

  defp finish({doc, code}) do
    %Segment{
      doc: doc |> Enum.reverse() |> Enum.join("\n") |> String.trim(),
      code: code |> Enum.reverse() |> trim_blank_lines()
    }
  end

  defp doc_line?(line), do: Regex.match?(@doc_line, line)

  defp code_has_content?(code), do: Enum.any?(code, &(String.trim(&1) != ""))

  defp strip("#"), do: ""
  defp strip("# " <> text), do: text

  defp trim_blank_lines(lines) do
    lines
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
  end
end
