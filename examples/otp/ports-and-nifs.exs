# Sooner or later Elixir code needs something outside
# the BEAM: a command-line tool, a C library, a Python
# script. There are two ways in, with opposite risks:
#
# - A *port* runs an external program as a separate OS
#   process and talks to it over stdin and stdout. If
#   the program crashes, the BEAM gets a message.
# - A *NIF* (native implemented function) loads compiled
#   C, Rust or Zig code into the BEAM itself. It's as
#   fast as a function call, and if it crashes, the
#   whole node goes down with it.
#
# `System.cmd/3` is the simplest port: run a program,
# wait for it to exit, and get its output and exit code.
IO.inspect(System.cmd("echo", ["hello"]), label: "echo")

# A failing program is just a non-zero exit code. Nothing
# crashes on the Elixir side.
IO.inspect(
  System.cmd("sh", ["-c", "echo oops >&2; exit 3"], stderr_to_stdout: true),
  label: "failing"
)

# `Port.open/2` keeps the program running and lets you
# talk to it. The port behaves like a process: the
# process that opened it (its *owner*) sends it data and
# receives `{port, {:data, ...}}` messages back.
cat = System.find_executable("cat")
port = Port.open({:spawn_executable, cat}, [:binary, :exit_status])

Port.command(port, "ping\n")
receive do: ({^port, {:data, data}} -> IO.inspect(data, label: "cat echoed"))
Port.close(port)

# If the program dies, even from `kill -9`, the owner
# gets its exit status as a message (137 is 128 + signal
# 9), and the node carries on.
sh = System.find_executable("sh")
port = Port.open({:spawn_executable, sh}, [:exit_status, args: ["-c", "kill -9 $$"]])
receive do: ({^port, {:exit_status, status}} -> IO.inspect(status, label: "killed program"))

# The other direction is the surprise. When the owner
# exits, the port closes, but that only closes the
# program's stdin. A program that never reads stdin
# keeps running. Here the owner starts `sleep 30` and
# exits at once.
me = self()

{_owner, ref} =
  spawn_monitor(fn ->
    sleep = System.find_executable("sleep")
    port = Port.open({:spawn_executable, sleep}, args: ["30"])
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    send(me, {:os_pid, Integer.to_string(os_pid)})
  end)

os_pid = receive do: ({:os_pid, os_pid} -> os_pid)
receive do: ({:DOWN, ^ref, :process, _, _} -> :ok)

# `kill -0` sends no signal, it only checks that the
# process exists. Exit code 0: `sleep` is still there.
running? = fn -> match?({_, 0}, System.cmd("kill", ["-0", os_pid], stderr_to_stdout: true)) end
IO.inspect(running?.(), label: "sleep still running after its owner died")

# Clean up the orphan ourselves, and wait until it's gone.
System.cmd("kill", [os_pid])
Stream.repeatedly(running?) |> Enum.find(&(&1 == false))
IO.inspect(running?.(), label: "after kill")

# > **Pitfall:** programs started from a port can outlive
# > the process (and even the node) that started them.
# > Use programs that exit when stdin closes, or a
# > wrapper that does it for them: the `muontrap` and
# > `erlexec` libraries kill the OS process when its
# > Elixir owner dies.
#
# > **Pitfall:** a NIF that crashes (a segfault, a
# > `panic` that isn't caught) takes the whole node down
# > with every process on it. No supervisor can help.
# > Prefer a port unless you need the speed. If you do
# > write a NIF, Rustler (Rust) is safer than raw C: it
# > catches Rust panics and raises them as Elixir errors.
#
# > **Pitfall:** the VM runs processes on a few
# > *schedulers*, usually one per CPU core. A NIF that
# > runs for more than about a millisecond blocks its
# > scheduler, and every process waiting on that
# > scheduler stalls. Long NIFs must run
# > on a dirty scheduler (see
# > [Schedulers and Reductions](/production/schedulers)).
#
# > **Pitfall:** `:os.cmd/1` and `System.shell/2` run a
# > string through the shell. With user input in that
# > string, that's shell injection. `System.cmd/3`
# > passes arguments as a list, with no shell between.
#
# **Go deeper:** [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-C)
# by Erik Stenman explains ports
# ([chapter 13](https://blog.stenmans.org/theBeamBook/#CH-IO)) and
# NIFs, BIFs and linked-in drivers (chapter 16).
