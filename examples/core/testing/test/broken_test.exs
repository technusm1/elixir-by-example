defmodule BrokenTest do
  # Wrong on purpose, to show what failures look like. Excluded by default.
  use ExUnit.Case, async: true
  @moduletag :broken

  test "a comparison" do
    assert Span.format(3_700) == "1h 2m"
  end

  test "a pattern" do
    assert {:ok, _} = Span.parse("1h30")
  end

  test "an exception" do
    assert_raise ArgumentError, fn -> Span.parse!("1h") end
  end
end
