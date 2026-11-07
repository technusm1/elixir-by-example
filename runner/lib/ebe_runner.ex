defmodule EbeRunner do
  @moduledoc """
  Evaluates one example per VM boot, like `elixir file.exs` does.

  Output is not captured here: stdout and stderr stream to the page through
  Popcorn's `onStdout`/`onStderr` callbacks, so long-running examples show
  progress as it happens. The reply only says whether the script succeeded.
  """
  use GenServer

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: :main)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call(["run", file, code], from, state) when is_binary(file) and is_binary(code) do
    # Evaluate outside the GenServer so a crashing or blocking example
    # can't take the evaluator down with it.
    spawn(fn -> GenServer.reply(from, run(file, code)) end)
    {:noreply, state}
  end

  # `Code.compile_string/2` is what `elixir file.exs` does (via
  # `Code.require_file/1`). `Code.eval_string/3` would go through the
  # interpreter instead, which formats some errors differently.
  defp run(file, code) do
    Code.compile_string(code, file)
    # Give output from processes the script started a moment to flush.
    Process.sleep(20)
    %{"ok" => true}
  rescue
    error -> failed(:error, error, __STACKTRACE__)
  catch
    kind, reason -> failed(kind, reason, __STACKTRACE__)
  end

  defp failed(kind, reason, stacktrace) do
    IO.write(:stderr, Exception.format(kind, reason, stacktrace))
    %{"ok" => false}
  end
end
