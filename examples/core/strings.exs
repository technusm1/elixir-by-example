# Strings are UTF-8 encoded binaries, written in double
# quotes.
s = "héllo"
IO.inspect(s)
IO.inspect(is_binary(s))

# Length in characters and size in bytes differ as
# soon as you leave ASCII.
IO.inspect(String.length(s))
IO.inspect(byte_size(s))

# Graphemes are what a reader sees as one character.
# Some, like flag emoji, are several codepoints.
flag = "🇮🇳"
IO.inspect(String.length(flag))
IO.inspect(String.codepoints(flag))
IO.inspect(byte_size(flag))

# The `String` module works on graphemes.
IO.inspect(String.upcase(s))
IO.inspect(String.reverse(s))
IO.inspect(String.split("a,b,,c", ","))
IO.inspect(String.split("  many   spaces  "))
IO.inspect(String.slice("elixir", 1..3))

# Interpolation calls `to_string/1` on the value.
n = 42
IO.puts("n is #{n}")

# Binaries can be pattern matched, which makes parsing
# prefixes cheap.
"user:" <> id = "user:1234"
IO.inspect(id)

<<first::utf8, rest::binary>> = s
IO.inspect(first)
IO.inspect(rest)

# Single quotes make a *charlist*: a list of integer
# codepoints, mostly for calling Erlang APIs. Modern
# Elixir prints them with the `~c` sigil.
IO.inspect(~c"abc")
IO.inspect(~c"abc" == [97, 98, 99])
IO.inspect(to_string(~c"abc"))

# > **Pitfall:** `'abc'` is not a string. It's a
# > charlist, and `"abc" == 'abc'` is `false`. Elixir
# > 1.20 emits a deprecation warning for single-quoted
# > charlists; write
# > `~c"abc"` when you really mean one.
#
# > **Pitfall:** `String.length/1` walks the whole
# > string (O(n)) and counts graphemes. If you need a
# > size limit for storage or the network, you want
# > `byte_size/1`, which is O(1).
