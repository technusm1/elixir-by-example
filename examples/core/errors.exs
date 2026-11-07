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
# of returning an error tuple.
try do
  File.read!("does-not-exist.txt")
rescue
  e in File.Error -> IO.puts("File.Error: " <> Exception.message(e))
end

# `rescue` matches on the exception module. `after`
# always runs, whether or not something was raised;
# use it to release resources.
try do
  raise ArgumentError, "bad input"
rescue
  e in ArgumentError -> IO.puts("rescued: " <> e.message)
after
  IO.puts("cleanup runs either way")
end

# Define your own exceptions with `defexception`.
# Give them fields and a `message/1` for context.
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

# In OTP systems you mostly *don't* rescue. A process
# that hits an unexpected error crashes, and its
# supervisor restarts it in a known-good state. See
# Supervisors in the Processes and OTP track.

# > **Pitfall:** `rescue e -> ...` with no exception
# > type catches *everything*, including bugs like
# > `FunctionClauseError` you'd want to see. Rescue the
# > specific exceptions you expect, or let it crash.
#
# > **Pitfall:** don't use `raise`/`rescue` for control
# > flow, like ending a loop early or signalling "not
# > found". Return tagged tuples; use `throw`/`catch`
# > only for rare non-local returns, mostly from
# > third-party callbacks.
