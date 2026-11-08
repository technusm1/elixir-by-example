defmodule Span.CLITest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  test "prints the total" do
    assert capture_io(fn -> Span.CLI.main(["1h", "30m"]) end) == "total: 1h 30m\n"
  end

  test "logs and skips a bad duration" do
    {output, log} = with_log(fn -> capture_io(fn -> Span.CLI.main(["1h", "oops"]) end) end)
    assert output == "total: 1h\n"
    assert log =~ ~s(skipping "oops")
  end
end
