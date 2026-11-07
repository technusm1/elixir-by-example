defmodule Ebe.SourceTest do
  use ExUnit.Case, async: true

  alias Ebe.Source
  alias Ebe.Source.Segment

  doctest Ebe.Source

  test "column-0 comments are prose, indented comments stay code" do
    source = """
    # Intro.
    defmodule A do
      # internal note
      def f, do: 1 # trailing
    end
    """

    assert [%Segment{doc: "Intro.", code: code}] = Source.segments(source)
    assert code =~ "# internal note"
    assert code =~ "# trailing"
  end

  test "a new prose block after code starts a new segment" do
    assert [%Segment{doc: "One", code: "a = 1"}, %Segment{doc: "Two", code: "b = 2"}] =
             Source.segments("# One\na = 1\n\n# Two\nb = 2\n")
  end

  test "bare # keeps paragraph breaks and trailing prose has no code" do
    assert [
             %Segment{code: "x = 1"},
             %Segment{doc: "> **Pitfall:** a\n\n> **Pitfall:** b", code: ""}
           ] =
             Source.segments("x = 1\n\n# > **Pitfall:** a\n#\n# > **Pitfall:** b\n")
  end

  test "blank lines around code are trimmed, inner blank lines kept" do
    assert [%Segment{code: "a = 1\n\nb = 2"}] = Source.segments("# Doc\n\na = 1\n\nb = 2\n\n")
  end

  test "#! shebang and #{} interpolation-like lines are not prose" do
    assert [%Segment{doc: "", code: ~S|IO.puts("#{1}")|}] =
             Source.segments("#!/usr/bin/env elixir\nIO.puts(\"\#{1}\")\n")
  end

  test "every registered example is registered exactly once" do
    assert Ebe.Catalog.unregistered_files() == []
  end
end
