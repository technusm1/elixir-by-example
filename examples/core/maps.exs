# Maps are Elixir's key-value data structure. Any
# value can be a key, and keys are unordered.
user = %{"name" => "Ada", "langs" => ["elixir", "erlang"]}
IO.inspect(user)

# When every key is an atom, there's a shorthand.
# This is by far the most common map in Elixir code.
config = %{port: 4000, host: "localhost"}
IO.inspect(config)

# Read with `map[key]`, which returns `nil` for a
# missing key, or with `map.key`, which only works for
# atom keys and *raises* if the key is missing.
IO.inspect(user["name"])
IO.inspect(user["email"])
IO.inspect(config.port)

# `Map.fetch/2` tells "missing" apart from "present
# but nil", and `Map.get/3` takes a default.
IO.inspect(Map.fetch(config, :port))
IO.inspect(Map.fetch(config, :tls))
IO.inspect(Map.get(config, :tls, false))

# Maps are immutable. "Updating" returns a new map;
# the original is untouched.
config2 = Map.put(config, :tls, true)
IO.inspect(config2)
IO.inspect(config)

# The `%{map | key: value}` syntax updates *existing*
# keys only. It raises `KeyError` for new keys, which
# is exactly what you want when a typo would otherwise
# silently add a key.
config3 = %{config | port: 8080}
IO.inspect(config3)

try do
  %{config | prot: 8080}
rescue
  e in KeyError -> IO.puts("KeyError: " <> Exception.message(e))
end

# Pattern matching pulls values out. A map pattern
# matches any map that has *at least* those keys.
%{host: host} = config
IO.puts("host is #{host}")

# Nested data: `put_in/2`, `update_in/3` and friends
# take a path into the structure.
state = %{users: %{"ada" => %{visits: 1}}}
state = update_in(state, [:users, "ada", :visits], &(&1 + 1))
IO.inspect(state)

# > **Pitfall:** don't rely on map ordering. Older
# > guides say small maps print sorted; on modern OTP
# > they don't (look at `config` above: `port` came
# > before `host`). If order matters, use a list or a
# > keyword list.
#
# > **Pitfall:** `%{"name" => 1}` and `%{name: 1}` are
# > different maps. JSON decoders give you string keys;
# > don't convert untrusted keys with
# > `String.to_atom/1`. Atoms are never garbage
# > collected, so this is a memory leak waiting for an
# > attacker.
