# A keyword list is a list of `{atom, value}` tuples,
# with special syntax. It's how Elixir passes options.
opts = [timeout: 5000, retries: 3]
IO.inspect(opts)
IO.inspect(opts == [{:timeout, 5000}, {:retries, 3}])

# Read values with `opts[:key]` or the `Keyword`
# module.
IO.inspect(opts[:timeout])
IO.inspect(Keyword.get(opts, :verbose, false))
IO.inspect(Keyword.fetch(opts, :retries))

# Unlike maps, keys are ordered and may repeat. The
# first occurrence wins on lookup.
dup = [level: :info, level: :debug]
IO.inspect(dup[:level])
IO.inspect(Keyword.get_values(dup, :level))

# `Keyword.put/3` replaces all existing entries for a
# key; `Keyword.merge/2` applies overrides.
IO.inspect(Keyword.put(dup, :level, :warn))
defaults = [timeout: 1000, retries: 1, verbose: false]
IO.inspect(Keyword.merge(defaults, opts))

# When a keyword list is the last argument, the
# brackets are optional. That's why `if` and `def`
# (both coming up) accept `do:`.
IO.inspect(String.split("a b c", " ", parts: 2))
IO.inspect(if(true, do: "yes", else: "no"))

# `Keyword.validate!/2` rejects unknown options and
# fills in defaults, so typos fail loudly.
IO.inspect(Keyword.validate!([retries: 5], retries: 1, timeout: 1000))

try do
  Keyword.validate!([retires: 5], retries: 1, timeout: 1000)
rescue
  e in ArgumentError -> IO.puts("ArgumentError: " <> Exception.message(e))
end

# > **Pitfall:** don't pattern match on keyword lists
# > like `[timeout: t] = opts`. It only matches if the
# > list has exactly those keys in exactly that order.
# > Use `Keyword.get/3` or `Keyword.validate!/2`.
