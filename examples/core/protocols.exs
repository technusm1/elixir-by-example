# Elixir has two ways to let one piece of code work
# with many kinds of things:
#
# - a **protocol** picks the implementation from the
#   *data*: one function name, a separate
#   implementation per type.
# - a **behaviour** is a contract for *modules*: a list
#   of functions a module promises to define, so you can
#   swap one module for another.
#
# ## Protocols
#
# Protocols are how `to_string/1`, `inspect/1` and
# `Enum` work on so many types.
defprotocol Describe do
  @doc "Returns a short human description."
  def describe(value)
end

# Implementations live with `defimpl`, for built-in
# types or your own structs, and can sit in a
# different module or library from the protocol.
# Strings are binaries, and protocols call that type
# `BitString`.
defimpl Describe, for: Integer do
  def describe(n) when n < 0, do: "a negative integer"
  def describe(_n), do: "an integer"
end

defimpl Describe, for: BitString do
  def describe(s), do: "a string of #{String.length(s)} characters"
end

defimpl Describe, for: List do
  def describe(list), do: "a list of #{length(list)} items"
end

IO.puts(Describe.describe(42))
IO.puts(Describe.describe(-1))
IO.puts(Describe.describe("héllo"))
IO.puts(Describe.describe([1, 2, 3]))

# Structs get their own implementation, separate from
# plain maps. (`struct/2` is `struct!/2` without the
# checks: it ignores unknown keys.)
defmodule Temp do
  defstruct [:celsius]
end

defimpl Describe, for: Temp do
  def describe(%{celsius: c}), do: "a temperature of #{c}°C"
end

IO.puts(Describe.describe(struct(Temp, celsius: 21)))

# Calling a protocol for a type with no
# implementation raises `Protocol.UndefinedError`.
try do
  Describe.describe(:an_atom)
rescue
  e in Protocol.UndefinedError ->
    IO.puts(e |> Exception.message() |> String.split("\n") |> hd())
end

# Built-in protocols plug your types into the
# language. Implementing `String.Chars` makes
# `to_string/1` and interpolation work; `@derive`
# picks a ready-made implementation. This one hides a
# field from `inspect`.
defmodule Account do
  @derive {Inspect, except: [:password]}
  defstruct [:login, :password]
end

defimpl String.Chars, for: Account do
  def to_string(%{login: login}), do: "account #{login}"
end

account = struct(Account, login: "ada", password: "hunter2")
IO.puts("Logged in as #{account}")
IO.inspect(account)

# ## Behaviours
#
# A behaviour lists *callbacks* with `@callback`, each
# with a typespec (see
# [Typespecs and Types](/core/typespecs)). Here: any
# module that can deliver a notification.
defmodule Notifier do
  @callback deliver(to :: String.t(), message :: String.t()) :: :ok | {:error, term()}
  @callback channel() :: String.t()
end

# A module adopts it with `@behaviour`. `@impl true`
# marks each function that implements a callback, so
# the compiler can check names and arities.
defmodule Sms do
  @behaviour Notifier

  @impl true
  def deliver(to, message), do: IO.puts("SMS to #{to}: #{message}")

  @impl true
  def channel, do: "sms"
end

defmodule Email do
  @behaviour Notifier

  @impl true
  def deliver(to, message), do: IO.puts("email to #{to}: #{message}")

  @impl true
  def channel, do: "email"
end

# A module name is just an atom, so it can live in a
# variable (or in config), and `module.function(...)`
# calls into whichever module is there. The code that
# sends doesn't know or care which one it got.
for notifier <- [Sms, Email] do
  notifier.deliver("ada", "your order shipped via #{notifier.channel()}")
end

# The checks are compile-time warnings. To show them
# without failing this page, compile a broken module
# from a string and collect the warnings as data:
# it misspells `deliver/2` and forgets `@impl` on
# `channel/0`.
broken = """
defmodule Pigeon do
  @behaviour Notifier
  def channel, do: "pigeon"
  @impl true
  def delivr(_to, _message), do: :ok
end
"""

{_, warnings} = Code.with_diagnostics(fn -> Code.compile_string(broken) end)
for w <- warnings, do: IO.puts(w.message |> String.split(". ") |> hd())

# `use Mod` runs the macro `Mod.__using__/1`, which
# injects code into your module: usually
# `@behaviour Mod` plus default implementations you
# may override. `quote` returns code instead of
# running it ([From Source to BEAM](/core/compilation)
# goes deeper). This is what `use GenServer` does in
# the Processes and OTP track.
defmodule Notifier.Base do
  defmacro __using__(_opts) do
    quote do
      @behaviour Notifier

      @impl true
      def channel, do: __MODULE__ |> Module.split() |> List.last() |> String.downcase()

      defoverridable channel: 0
    end
  end
end

defmodule Slack do
  use Notifier.Base

  @impl true
  def deliver(to, message), do: IO.puts("Slack DM to #{to}: #{message}")
end

Slack.deliver("ada", "deploy finished")
IO.inspect(Slack.channel(), label: "default channel")

# When to use which:
#
# - **Protocol** when the behavior depends on the
#   *type of a value*, and other people should be able
#   to add types: printing, encoding, enumerating.
# - **Behaviour** when you swap *whole modules*: a
#   storage backend, a payment provider, a test double,
#   or the callbacks OTP calls in a GenServer.

# > **Pitfall:** prefer a protocol over a big
# > `case`/`cond` on types when *other people* need to
# > add types later. If every type is yours and known
# > up front, plain pattern matching in function heads
# > is simpler.
#
# > **Pitfall:** a behaviour is only checked with
# > warnings. A module that misses a callback still
# > compiles, and calling the missing function raises
# > `UndefinedFunctionError` at runtime. Make your
# > build treat warnings as errors
# > ([Mix Projects](/core/mix) shows how).
#
# > **Pitfall:** `@derive {Inspect, except: [...]}`
# > only hides values from `inspect`, such as logs and
# > crash reports. The data is still in the struct and
# > still serialized by JSON encoders unless you
# > exclude it there too.
