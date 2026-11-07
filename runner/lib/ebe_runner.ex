defmodule EbeRunner do
  @moduledoc """
  Evaluates one example per VM boot, like `elixir file.exs` does.

  Output is not captured here: stdout and stderr stream to the page through
  Popcorn's `onStdout`/`onStderr` callbacks, so long-running examples show
  progress as it happens. The reply says whether the script succeeded and
  carries compiler diagnostics with their line numbers, so the page can show
  each warning under the cell it belongs to.

  `["run", file, code, partial]`: when `partial` is true the page is running
  only the first cells of an example ("Run to here"). Variables bound there are
  often used by later cells that didn't run, so "variable is unused" warnings
  are dropped for partial runs; every other diagnostic is still printed.
  """
  use GenServer

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: :main)

  @impl true
  def init(nil) do
    # The page shows plain text; terminal colour codes would print as garbage.
    Application.put_env(:elixir, :ansi_enabled, false)
    {:ok, nil}
  end

  @impl true
  def handle_call(["run", file, code, partial], from, state)
      when is_binary(file) and is_binary(code) and is_boolean(partial) do
    # Evaluate outside the GenServer so a crashing or blocking example
    # can't take the evaluator down with it.
    spawn(fn -> GenServer.reply(from, run(file, code, partial)) end)
    {:noreply, state}
  end

  # `Code.compile_string/2` is what `elixir file.exs` does (via
  # `Code.require_file/1`). `Code.eval_string/3` would go through the
  # interpreter instead, which formats some errors differently.
  defp run(file, code, partial) do
    {result, diagnostics} = Code.with_diagnostics(fn -> compile(file, code) end)

    diagnostics =
      for d <- diagnostics, not (partial and unused_variable?(d)) do
        %{"severity" => Atom.to_string(d.severity), "message" => d.message, "line" => line(d)}
      end

    Map.put(result, "diagnostics", diagnostics)
  end

  defp compile(file, code) do
    Code.compile_string(code, file)
    # Give output from processes the script started a moment to flush.
    Process.sleep(20)
    %{"ok" => true}
  rescue
    error -> failed(:error, error, user_frames(__STACKTRACE__))
  catch
    kind, reason -> failed(kind, reason, user_frames(__STACKTRACE__))
  end

  # Like IEx: hide the compiler's and this runner's own frames, keep the ones
  # from the example and from the libraries it called.
  @internal [
    :elixir,
    :elixir_compiler,
    :elixir_lexical,
    :elixir_module,
    :elixir_dispatch,
    Module.ParallelChecker,
    Code,
    __MODULE__
  ]
  defp user_frames(stacktrace) do
    Enum.reject(stacktrace, fn {mod, _fun, _arity, _loc} -> mod in @internal end)
  end

  defp unused_variable?(%{severity: :warning, message: message}),
    do: message =~ ~r/^variable "[^"]+" is unused/

  defp unused_variable?(_diagnostic), do: false

  defp line(%{position: {line, _col}}), do: line
  defp line(%{position: line}) when is_integer(line), do: line
  defp line(_diagnostic), do: nil

  defp failed(kind, reason, stacktrace) do
    IO.write(:stderr, Exception.format(kind, reason, stacktrace))
    %{"ok" => false}
  end
end
