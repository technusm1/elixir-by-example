# Elixir has two ways to signal failure. *Expected*
# failures (a missing file, bad user input) are
# return values: `{:ok, value}` or `{:error, reason}`.
IO.inspect(File.read("does-not-exist.txt"))
IO.inspect(Integer.parse("12abc"))

# The caller decides what to do, usually with `case`
# or `with`.
case File.read("does-not-exist.txt") do
  {:ok, contents} -> IO.puts(contents)
  {:error, :enoent} -> IO.puts("no such file, using defaults")
end

# *Unexpected* failures raise exceptions. By
# convention, a function ending in `!` raises instead
# of returning an error tuple. `try` runs a block, and
# its `rescue` clauses match on the exception module:
# `e in File.Error` binds the exception to `e`.
try do
  File.read!("does-not-exist.txt")
rescue
  e in File.Error -> IO.puts("File.Error: " <> Exception.message(e))
end

# A clause can list several exception modules. `after`
# always runs, whether or not something was raised;
# use it to release resources. It doesn't change the
# value of the `try`.
try do
  raise ArgumentError, "bad input"
rescue
  e in [ArgumentError, RuntimeError] -> IO.puts("rescued: " <> e.message)
after
  IO.puts("cleanup runs either way")
end

# A function body is an implicit `try`: `rescue`,
# `catch` and `after` can go straight after it.
defmodule Parse do
  def int(text) do
    String.to_integer(text)
  rescue
    ArgumentError -> :not_a_number
  end
end

IO.inspect(Parse.int("12"), label: "int")
IO.inspect(Parse.int("ab"), label: "int")

# Define your own exceptions with `defexception`.
# Give them fields and a `message/1` for context.
# Exceptions are a behaviour (see
# [Protocols and Behaviours](/core/protocols)), so
# `@impl true` marks `message/1` as its callback.
defmodule InsufficientFunds do
  defexception [:needed, :available]

  @impl true
  def message(e), do: "needed #{e.needed}, only #{e.available} available"
end

defmodule Bank do
  def withdraw(balance, amount) when amount <= balance, do: {:ok, balance - amount}
  def withdraw(balance, amount), do: {:error, {:insufficient, amount, balance}}

  def withdraw!(balance, amount) do
    case withdraw(balance, amount) do
      {:ok, new_balance} -> new_balance
      {:error, {:insufficient, a, b}} -> raise InsufficientFunds, needed: a, available: b
    end
  end
end

IO.inspect(Bank.withdraw(100, 30))
IO.inspect(Bank.withdraw(100, 300))

try do
  Bank.withdraw!(100, 300)
rescue
  e in InsufficientFunds -> IO.puts("InsufficientFunds: " <> Exception.message(e))
end

# Offering both `withdraw/2` and `withdraw!/2`, as the
# standard library does, lets callers choose: handle
# the error, or crash if it "can't happen".
IO.inspect(Bank.withdraw!(100, 30), label: "withdraw!")

# `raise` is one of three kinds of failure. The other
# two are `throw` and `exit`, and `rescue` sees
# neither: they need `catch`.
#
# `throw` jumps out of deeply nested code with a
# value, and `catch` receives it. Here it stops the
# search at the first negative number.
rows = [[3, 1], [4, -1, 5], [-9, 2]]

first_negative =
  try do
    Enum.each(rows, fn row ->
      Enum.each(row, fn x -> if x < 0, do: throw({:found, x}) end)
    end)

    :none
  catch
    {:found, x} -> x
  end

IO.inspect(first_negative, label: "throw/catch")

# That works, but the standard library usually has a
# function that stops early by itself, and it says
# what it does. Reach for `throw` only when code you
# don't control (a callback, a library) gives you no
# other way out.
IO.inspect(Enum.find_value(rows, fn row -> Enum.find(row, &(&1 < 0)) end), label: "find_value")

# Every Elixir program runs inside a *process* (the
# Processes and OTP track is about them). `exit/1`
# stops the current process with a reason. It's how
# processes signal that they're finished or broken,
# and other processes can watch for it.
#
# `catch kind, value` catches all three kinds and
# tells you which one it was.
kinds = [
  fn -> raise "boom" end,
  fn -> throw(:found) end,
  fn -> exit(:shutdown) end
]

for fun <- kinds do
  try do
    fun.()
  catch
    :error, e -> IO.inspect(e.__struct__, label: ":error")
    :throw, value -> IO.inspect(value, label: ":throw")
    :exit, reason -> IO.inspect(reason, label: ":exit")
  end
end

# When to use which:
#
# - **`{:ok, _}` / `{:error, _}`**: anything the caller
#   should expect and handle. The default.
# - **`raise`**: bugs and broken assumptions, and the
#   `!` variants. Rescue only what you can recover
#   from.
# - **`throw`**: rare non-local returns, mostly out of
#   callbacks.
# - **`exit`**: stopping a process. You'll catch
#   `:exit` mostly around calls to other processes,
#   which exit the caller when they time out.
#
# In OTP systems you mostly *don't* rescue. A process
# that hits an unexpected error crashes, and its
# supervisor restarts it in a known-good state. See
# [Supervisors](/otp/supervisors).

# > **Pitfall:** `rescue e -> ...` with no exception
# > type catches *every* exception, including bugs like
# > `FunctionClauseError` you'd want to see. Rescue the
# > specific exceptions you expect, or let it crash.
#
# > **Pitfall:** `catch _, _` is broader still: it also
# > swallows throws and exits, such as the exit a
# > timed-out call to another process raises, so a dead
# > or overloaded server goes unnoticed.
#
# > **Pitfall:** don't use `raise`/`rescue` for control
# > flow, like ending a loop early or signalling "not
# > found". Return tagged tuples.
