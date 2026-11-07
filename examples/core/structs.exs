# A struct is a map with a fixed set of keys, defined
# in a module and named after it. It gives a shape a
# name, defaults, and compile-time key checking.
defmodule User do
  @enforce_keys [:email]
  defstruct [:email, name: "anonymous", admin?: false]

  # A constructor is the idiomatic place to validate.
  def new(fields) do
    user = struct!(__MODULE__, fields)

    if String.contains?(user.email, "@"),
      do: {:ok, user},
      else: {:error, :invalid_email}
  end
end

# `@enforce_keys` makes a key required. Other keys
# fall back to their defaults (or `nil`).
{:ok, user} = User.new(email: "ada@example.com")
IO.inspect(user)
IO.inspect(User.new(email: "nope"))

# Access fields with dot syntax.
IO.puts(user.email)
IO.puts(user.name)

# Update with the same `|` syntax as maps. Only
# existing keys are allowed.
admin = %{user | admin?: true, name: "Ada"}
IO.inspect(admin)

# Pattern match on the struct name to accept only that
# type. Function heads like this are how Elixir code
# dispatches on "type". A misspelled field in
# `%User{...}` is a *compile* error, not a silent new
# key.
defmodule Greeter do
  def greet(%User{admin?: true, name: name}), do: "Welcome back, admin #{name}"
  def greet(%User{name: name}), do: "Hello, #{name}"
end

IO.puts(Greeter.greet(user))
IO.puts(Greeter.greet(admin))

# Under the hood a struct is a map with a special
# `__struct__` key, so `Map` functions work on it.
IO.inspect(Map.keys(user) |> Enum.sort(), label: "keys")
IO.inspect(is_map(user), label: "is_map")
IO.inspect(user.__struct__, label: "__struct__")

# Leaving out an enforced key raises.
try do
  struct!(User, name: "no email")
rescue
  e in ArgumentError -> IO.puts("ArgumentError: " <> Exception.message(e))
end

# Structs don't get map *behaviours* for free: no
# `user[:email]` (Access) and no `Enum.count(user)`
# (Enumerable).
try do
  Enum.count(user)
rescue
  e in Protocol.UndefinedError -> IO.puts(e |> Exception.message() |> String.split("\n") |> hd())
end

# > **Pitfall:** `user[:email]` fails on structs
# > because they don't implement `Access`. Use
# > `user.email`, or `Map.get/2` when the key is
# > dynamic. Agents used to map-heavy code often reach
# > for brackets here.
#
# > **Pitfall:** in a single `.exs` script, top-level
# > code can't use the `%User{}` literal for a struct
# > defined in the same file ("cannot access struct
# > User ... in the same context that defines it").
# > Use a constructor like `User.new/1` or `struct!/2`,
# > or use the literal inside another module, as
# > `Greeter` does. In a Mix project this never comes
# > up.
