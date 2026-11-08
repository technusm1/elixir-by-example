defmodule Ebe.Runner do
  @moduledoc """
  Executes an example on the real BEAM and captures its output.

  Each example runs as `elixir <file>` in a fresh OS process, inside a throwaway
  working directory, with a hard timeout. A run is only successful when:

    * the process exits with status 0,
    * it finishes within the timeout, and
    * the output contains no compiler or type-checker warnings.

  That last rule is what makes the site trustworthy: Elixir 1.20's type checker
  reports provable type errors as warnings, and we treat every warning as a
  broken example.
  """

  @timeout_ms 30_000
  # A walkthrough may fetch and compile dependencies and start several nodes.
  @walk_timeout_ms 180_000

  @type result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Raises unless child `elixir` processes run the same Elixir and OTP versions
  as the build itself, so the versions printed on the site are the real ones.
  """
  @spec check_toolchain!() :: :ok
  def check_toolchain! do
    {elixir, search_path} = toolchain()
    expected = "#{System.version()} #{System.otp_release()}"

    {out, 0} =
      System.cmd(elixir, ["-e", ~S|IO.write("#{System.version()} #{System.otp_release()}")|],
        env: [{"PATH", search_path}],
        cd: System.tmp_dir!()
      )

    if out != expected do
      raise "examples would run on Elixir/OTP #{out}, but the build runs #{expected}"
    end

    :ok
  end

  @doc """
  Runs `source` as if it were the file at `path` (same basename, so error
  messages name the right file) and returns its combined stdout/stderr.
  `args` go to `elixir` before the file, e.g. `["--name", "a@127.0.0.1"]`.
  """
  @spec run(Path.t(), String.t(), [String.t()]) :: result()
  def run(path, source, args \\ []) do
    workdir = Path.join(System.tmp_dir!(), "ebe-run-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workdir)
    script = Path.join(workdir, Path.basename(path))
    File.write!(script, source)

    try do
      script |> exec(workdir, args) |> check(path)
    after
      File.rm_rf!(workdir)
    end
  end

  # Use the exact toolchain running this build, never whatever `elixir` happens
  # to be on PATH: version managers like asdf resolve shims per directory, and
  # examples run in a temp dir, which would silently pick a different version.
  defp toolchain do
    elixir_bin = Path.expand("../../bin", :code.lib_dir(:elixir))
    erlang_bin = Path.join(:code.root_dir(), "bin")
    elixir = Path.join(elixir_bin, "elixir")

    unless File.regular?(elixir), do: raise("elixir executable not found at #{elixir}")

    path = Enum.join([erlang_bin, elixir_bin, System.get_env("PATH", "")], ":")
    {elixir, path}
  end

  defp exec(path, workdir, args) do
    {elixir, search_path} = toolchain()
    env = [{~c"PATH", String.to_charlist(search_path)}, {~c"MIX_ENV", ~c"prod"}]
    spawn_collect(elixir, args ++ [path], workdir, env, @timeout_ms)
  end

  defp spawn_collect(executable, args, workdir, env, timeout_ms) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: args,
        cd: workdir,
        env: [{~c"NO_COLOR", ~c"1"} | env]
      ])

    collect(port, [], System.monotonic_time(:millisecond) + timeout_ms)
  end

  @doc """
  Runs a walkthrough (see `Ebe.Walkthrough`): copies the project files from
  `dir` into a throwaway directory, then runs all its `sh` blocks there in
  *one* `/bin/sh -e` session, as a reader would in one terminal: variables,
  functions and background processes from one block are still there in the
  next. Returns each block's combined output.

  A marker printed before each block splits the output. A block marked
  `fails` runs in a subshell as an `if` condition, so its failure doesn't end
  the session; its exit status is that of its last command, and the session
  stops if that is zero. Any other failing command stops the session too.
  Output containing a compiler warning is a failure. `MIX_ENV` is unset, so
  the walkthrough states it wherever it matters.
  """
  @spec run_walkthrough(Path.t(), [Ebe.Walkthrough.Block.t()]) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def run_walkthrough(dir, blocks) do
    workdir = Path.join(System.tmp_dir!(), "ebe-walk-#{System.unique_integer([:positive])}")

    for rel <- Ebe.Walkthrough.files(dir) do
      dest = Path.join(workdir, rel)
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(Path.join(dir, rel), dest)
    end

    {_elixir, search_path} = toolchain()
    env = [{~c"PATH", String.to_charlist(search_path)}, {~c"MIX_ENV", false}]
    sh = Enum.filter(blocks, &(&1.kind == :sh))

    try do
      result = spawn_collect("/bin/sh", ["-e", "-c", session(sh)], workdir, env, @walk_timeout_ms)
      check_session(result, length(sh), rel(dir))
    after
      remove_when_released(workdir, 50)
    end
  end

  # A release that was just told to stop may still be writing its logs into
  # the project for a moment, so deleting the directory can race with it.
  defp remove_when_released(dir, tries) do
    case File.rm_rf(dir) do
      {:ok, _} ->
        :ok

      {:error, _, _} when tries > 1 ->
        Process.sleep(100)
        remove_when_released(dir, tries - 1)

      {:error, reason, path} ->
        raise File.Error, reason: reason, action: "remove", path: path
    end
  end

  @marker "\u001E"

  defp session(blocks) do
    blocks
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {block, n} ->
      mark = "printf '\\036#{n}\\036'"

      if block.fails do
        "#{mark}\nif (\n#{block.text}\n); then echo 'ebe: block #{n} is marked fails but succeeded'; exit 97; fi"
      else
        "#{mark}\n#{block.text}"
      end
    end)
  end

  defp check_session({status, out}, count, name) do
    [_before | parts] = String.split(out, @marker)
    outputs = parts |> Enum.chunk_every(2) |> Enum.map(fn [_n | text] -> Enum.join(text) end)
    reached = length(outputs)
    last = List.last(outputs) || out

    cond do
      status == :timeout ->
        {:error,
         "#{name}: walkthrough timed out after #{@walk_timeout_ms}ms in sh block #{reached}:\n\n#{last}"}

      status != 0 ->
        {:error, "#{name}: sh block #{reached} failed (exit status #{status}):\n\n#{last}"}

      reached != count ->
        {:error, "#{name}: only #{reached} of #{count} sh blocks ran:\n\n#{out}"}

      (n = Enum.find_index(outputs, &(&1 =~ ~r/^\s*warning: /m))) != nil ->
        {:error,
         "#{name}: sh block #{n + 1} emitted warnings (treated as errors):\n\n#{Enum.at(outputs, n)}"}

      true ->
        {:ok, outputs}
    end
  end

  defp collect(port, acc, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, [acc | data], deadline)

      {^port, {:exit_status, status}} ->
        {status, IO.iodata_to_binary(acc)}
    after
      remaining ->
        kill(port)
        {:timeout, IO.iodata_to_binary(acc)}
    end
  end

  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("kill", ["-9", Integer.to_string(pid)])
      nil -> :ok
    end

    Port.close(port)
  catch
    :error, :badarg -> :ok
  end

  defp check({0, output}, path) do
    if output =~ ~r/^\s*warning: /m do
      {:error, "#{rel(path)} emitted warnings (treated as errors):\n\n#{output}"}
    else
      {:ok, output}
    end
  end

  defp check({:timeout, output}, path),
    do: {:error, "#{rel(path)} timed out after #{@timeout_ms}ms:\n\n#{output}"}

  defp check({status, output}, path),
    do: {:error, "#{rel(path)} exited with status #{status}:\n\n#{output}"}

  defp rel(path), do: Path.relative_to_cwd(path)

  @doc """
  Replaces values that differ between runs (pids, refs, ports, timings) so
  BEAM output can be compared with Popcorn output.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(output) do
    output
    |> String.replace(~r/#PID<\d+\.\d+\.\d+>/, "#PID<_>")
    |> String.replace(~r/#Reference<[\d.]+>/, "#Reference<_>")
    |> String.replace(~r/#Port<[\d.]+>/, "#Port<_>")
    |> String.replace(~r/#Function<[^>]+>/, "#Function<_>")
  end
end
