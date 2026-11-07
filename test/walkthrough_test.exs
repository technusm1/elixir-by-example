defmodule Ebe.WalkthroughTest do
  use ExUnit.Case, async: true

  alias Ebe.Walkthrough

  doctest Ebe.Walkthrough

  @text """
  Intro.

  ```file mix.exs
  ```

  ```sh
  mix compile
  ```
  """

  test "check accepts a walkthrough that shows every file once and runs something" do
    assert Walkthrough.check(Walkthrough.parse(@text), ["mix.exs"]) == :ok
  end

  test "check rejects missing, unshown and duplicated files" do
    blocks = Walkthrough.parse(@text)
    assert {:error, "shows files that don't exist" <> _} = Walkthrough.check(blocks, [])
    assert {:error, "never shows" <> _} = Walkthrough.check(blocks, ["mix.exs", "lib/a.ex"])

    twice = Walkthrough.parse(@text <> "\n```file mix.exs\n```\n")
    assert {:error, "shows twice" <> _} = Walkthrough.check(twice, ["mix.exs"])
  end

  test "prompts go before commands only" do
    script = "# build\nmix compile \\\n  --force\nfor i in 1 2; do\n  echo $i\ndone\n\nls"

    assert script |> Walkthrough.prompted() |> Enum.map(&elem(&1, 0)) ==
             [:comment, :command, :continued, :command, :continued, :continued, :blank, :command]
  end

  test "a one-line loop doesn't swallow the next command's prompt" do
    kinds = "until true; do sleep 1; done\nls" |> Walkthrough.prompted() |> Enum.map(&elem(&1, 0))
    assert kinds == [:command, :command]
  end

  test "an unclosed fence is an error" do
    assert_raise ArgumentError, fn -> Walkthrough.parse("```sh\nls\n") end
  end
end
