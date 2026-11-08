defmodule Span.LimitTest do
  # Changes the application environment, which every test can see: not async.
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:span, :max_seconds, 60)
    on_exit(fn -> Application.delete_env(:span, :max_seconds) end)
  end

  test "rejects durations over the configured limit" do
    assert Span.parse("1m") == {:ok, 60}
    assert Span.parse("61s") == {:error, {:too_long, 61}}
  end
end
