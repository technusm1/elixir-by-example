# A protocol is polymorphism for data: one function
# name, a separate implementation per type. It's how
# `to_string/1`, `inspect/1` and `Enum` work on so
# many types.
defprotocol Describe do
  @doc "Returns a short human description."
  def describe(value)
end

# Implementations live with `defimpl`, for built-in
# types or your own structs, and can sit in a
# different module or library from the protocol.
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
# plain maps.
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
# picks a ready-made implementation, here one that
# hides a field from `inspect`.
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

# > **Pitfall:** prefer a protocol over a big
# > `case`/`cond` on types when *other people* need to
# > add types later. If every type is yours and known
# > up front, plain pattern matching in function heads
# > is simpler.
#
# > **Pitfall:** `@derive {Inspect, except: [...]}`
# > only hides values from `inspect`, such as logs and
# > crash reports. The data is still in the struct and
# > still serialized by JSON encoders unless you
# > exclude it there too.
