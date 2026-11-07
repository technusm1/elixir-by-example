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

  @doc "Runs the example at `path` and returns its combined stdout/stderr."
  @spec run(Path.t()) :: result()
  def run(path) do
    path = Path.expand(path)
    workdir = Path.join(System.tmp_dir!(), "ebe-run-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workdir)

    try do
      path |> exec(workdir) |> check(path)
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

  defp exec(path, workdir) do
    {elixir, search_path} = toolchain()

    port =
      Port.open({:spawn_executable, elixir}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: [path],
        cd: workdir,
        env: [
          {~c"PATH", String.to_charlist(search_path)},
          {~c"MIX_ENV", ~c"prod"},
          {~c"NO_COLOR", ~c"1"}
        ]
      ])

    collect(port, [], System.monotonic_time(:millisecond) + @timeout_ms)
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
