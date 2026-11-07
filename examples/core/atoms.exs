# An atom is a constant whose value is its own name.
# Atoms label things: statuses, options, message tags.
IO.inspect(:ok)
IO.inspect(:error)
IO.inspect(:ok == :ok)

# Atoms with spaces or odd characters need quotes.
IO.inspect(:"hello world")

# `true`, `false` and `nil` are atoms too.
IO.inspect(is_atom(true))
IO.inspect(is_atom(nil))
IO.inspect(true == true)

# Module names are atoms with an `Elixir.` prefix.
# Erlang modules are plain lowercase atoms, called the
# same way.
IO.inspect(is_atom(String))
IO.inspect(String == :"Elixir.String")
IO.inspect(:math.sqrt(16))

# The idiom you'll see everywhere: tagged tuples, an
# atom first saying what happened.
IO.inspect(File.read("does-not-exist.txt"))
IO.inspect(Integer.parse("42abc"))

# Converting between atoms and strings.
IO.inspect(Atom.to_string(:hello))
IO.inspect(String.to_existing_atom("hello"))

try do
  String.to_existing_atom("never_seen_before_xyz")
rescue
  e in ArgumentError -> IO.puts("ArgumentError: " <> Exception.message(e))
end

# > **Pitfall:** atoms are never garbage collected and
# > the VM has a limit (about a million by default).
# > Hitting it crashes the whole node. Never call
# > `String.to_atom/1` on user input, JSON keys or
# > anything external; use `String.to_existing_atom/1`
# > or keep strings.
