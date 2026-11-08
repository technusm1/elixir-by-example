defmodule SpanTest do
  use ExUnit.Case, async: true
  doctest Span

  describe "parse/1" do
    test "adds up every unit" do
      assert Span.parse("1d2h3m4s") == {:ok, 93_784}
    end

    test "returns the reason for bad input" do
      assert {:error, {:unknown_unit, unit}} = Span.parse("5w")
      assert unit == "w"
      assert {:error, {:missing_unit, 5}} = Span.parse("5")
      refute match?({:ok, _}, Span.parse("h"))
    end

    for {text, seconds} <- [{"0s", 0}, {"45s", 45}, {"2m", 120}, {"1h1s", 3_601}] do
      test "parses #{text}" do
        assert Span.parse(unquote(text)) == {:ok, unquote(seconds)}
      end
    end
  end

  describe "parse!/1" do
    test "raises on bad input" do
      assert_raise ArgumentError, ~r/bad duration "5w"/, fn -> Span.parse!("5w") end
    end
  end

  describe "format/1" do
    setup do
      %{week: 7 * 86_400}
    end

    test "skips zero parts", %{week: week} do
      assert Span.format(week + 5) == "7d 5s"
    end

    test "round-trips through parse!/1", %{week: week} do
      for seconds <- [0, 59, 3_600, week] do
        assert seconds |> Span.format() |> String.replace(" ", "") |> Span.parse!() == seconds
      end
    end
  end
end
