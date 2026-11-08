# A *bitstring* is a sequence of bits, written between
# `<<` and `>>`. Three nested kinds share this syntax:
#
# - a **bitstring** has any number of bits;
# - a **binary** is a bitstring whose size is a whole
#   number of bytes;
# - a **string** is a binary that is valid UTF-8.
#
# Each comma-separated value is a *segment*. By
# default a segment is one byte.
bytes = <<104, 105>>
IO.inspect(bytes)
IO.inspect(bytes == "hi")

# Four bits are a bitstring but not a binary. Two
# bytes that aren't valid UTF-8 are a binary but not a
# string.
nibble = <<5::4>>
IO.inspect(nibble)
IO.inspect(is_bitstring(nibble))
IO.inspect(is_binary(nibble))

junk = <<0xFF, 0xFE>>
IO.inspect(is_binary(junk))
IO.inspect(String.valid?(junk))
IO.inspect(String.valid?("héllo"))

# `?a` is the integer codepoint of a character, handy
# when you build or match bytes by hand.
IO.inspect(?a)
IO.inspect(?é)
IO.inspect(<<?o, ?k>>)

# `IO.inspect` prints a binary as a string when it is
# printable, and as `<<...>>` bytes otherwise. For
# readable hex, pass `base: :hex` or use `Base`.
data = <<0, 1, 127, 128, 255>>
IO.inspect(data)
IO.inspect(data, base: :hex)
IO.puts(Base.encode16(data))
IO.inspect(Base.decode16!("CAFE"))

# ## Segment types and sizes
#
# `::` after a value says how to encode it: a size in
# bits (`::16`, or `::size(n)` when it's a variable),
# a type, an endianness. Multi-byte integers are
# big-endian unless you say otherwise. `base: :binary`
# shows the bits; `0x` and `0b` write integers in hex
# and binary.
IO.inspect(<<1::16>>)
IO.inspect(<<1::16-little>>)
IO.inspect(<<0b101::3, 0b00001::5>>, base: :binary)
width = 12
IO.inspect(<<1::size(width)>>)
IO.inspect(<<1.5::float-32>>, base: :hex)
IO.inspect(<<"é"::binary, ?é::utf8>>)

# `bit_size/1` counts bits, `byte_size/1` counts whole
# bytes, rounding up.
IO.inspect(bit_size(<<1::12>>))
IO.inspect(byte_size(<<1::12>>))

# A value too big for its segment keeps only its low
# bits. `<<300>>` is a single byte, 300 - 256:
<<b>> = <<300>>
IO.inspect(b)

# ## Building and matching are the same syntax
#
# Put `<<>>` on the left of `=` and it becomes a
# pattern: the match binds its variables, or raises
# `MatchError` if the bits don't fit. The modifiers
# decide how bits are read back, so the same four
# bytes mean different things.
four = <<0, 0, 1, 0>>
<<n::32>> = four
IO.inspect(n)
<<n_le::32-little>> = four
IO.inspect(n_le)
<<hi::16, lo::16>> = four
IO.puts("hi=#{hi} lo=#{lo}")
<<f::float-32>> = <<1.5::float-32>>
IO.inspect(f)

# Bytes are unsigned unless you ask for `signed`,
# which reads the top bit as a minus sign.
<<u::8>> = <<255>>
<<i::8-signed>> = <<255>>
IO.puts("unsigned #{u}, signed #{i}")

# `::binary` takes "the rest". With `-size(n)` it takes
# exactly n bytes, and `::bits` takes any number of
# bits.
<<tag::binary-size(3), body::binary>> = "GET /index.html"
IO.inspect(tag)
IO.inspect(body)
<<flag::1, rest::bits>> = <<0b1010_0000>>
IO.inspect(flag)
IO.inspect(rest)

# ## Parsing a wire protocol
#
# Here is why this matters. A common network framing
# is a 2-byte length followed by that many bytes of
# payload. TCP hands you a stream, so a read can hold
# several messages and the start of the next one.
#
# A size can use a variable bound *earlier in the same
# pattern*, so `len` read from the first two bytes
# tells `binary-size(len)` how much to take.
stream = <<5::16, "hello", 12::16, "binary world", 9::16, "par">>
IO.inspect(stream, base: :hex)

<<len::16, msg1::binary-size(len), stream::binary>> = stream
IO.inspect(msg1)
<<len::16, msg2::binary-size(len), stream::binary>> = stream
IO.inspect(msg2)

# The third message announces 9 bytes but only 3 have
# arrived. `case` tries each pattern in turn and runs
# the first that matches. `_` matches anything and
# throws it away; a bare variable like `partial`
# matches anything and keeps it, here the leftover
# bytes to prepend to the next read.
case stream do
  <<len::16, msg::binary-size(len), _::binary>> ->
    IO.puts("complete: #{msg}")

  partial ->
    IO.puts("waiting, #{byte_size(partial)} bytes buffered")
end

# Without bit syntax this is index arithmetic:
# `len = (buf[0] << 8) | buf[1]`, then
# `buf[2 .. 2 + len]`, then a bounds check you
# hopefully remembered. The pattern *is* the format
# spec, and a too-short buffer simply fails to match
# instead of reading garbage.

# ## Bit fields: an IPv4 header
#
# Not every field is a whole byte. An IPv4 header
# packs the version and header length into one byte,
# and three flags plus a 13-bit offset into two. Let's
# build a real 20-byte header for a packet from
# 192.168.1.10 to 8.8.8.8.
header =
  <<4::4, 5::4, 0::8, 60::16, 0x1C46::16, 0b010::3, 0::13, 64::8, 6::8, 0x4CB4::16, 192, 168, 1,
    10, 8, 8, 8, 8>>

IO.inspect(byte_size(header))
IO.puts(Base.encode16(header))

# Parsing it is one match that reads like the diagram
# in RFC 791. Names starting with `_` mark fields we
# skip.
<<version::4, ihl::4, _tos::8, total_length::16, _id::16, _reserved::1, dont_fragment::1,
  more_fragments::1, _frag_offset::13, ttl::8, protocol::8, _checksum::16, s1, s2, s3, s4, d1, d2,
  d3, d4>> = header

IO.puts("IPv#{version}, header #{ihl * 4} bytes, total #{total_length}")
IO.puts("DF=#{dont_fragment} MF=#{more_fragments} TTL=#{ttl} protocol=#{protocol}")
IO.puts("#{s1}.#{s2}.#{s3}.#{s4} -> #{d1}.#{d2}.#{d3}.#{d4}")

# A literal in a pattern must match exactly, so you
# can also *check* while you parse: this only matches
# IPv4 TCP packets.
<<4::4, _::68, 6::8, _::binary>> = header
IO.puts("it's TCP over IPv4")

# ## Which one to use
#
# - **Strings** for text people read. Use the `String`
#   module, which understands graphemes.
# - **Binaries** for bytes: file formats, network
#   protocols, hashes, encrypted data. Use `byte_size`
#   and bit syntax, not `String` functions.
# - **Bitstrings** when fields aren't byte-aligned:
#   flags, nibbles, compressed or packed formats.
#   They usually exist only inside a match; what you
#   store or send is a binary.

# > **Pitfall:** a value that doesn't fit its segment
# > is silently truncated to its low bits, with no
# > error: `<<300>>` above came back as 44.
#
# > **Pitfall:** in a pattern, an unsized `::binary`
# > or `::bits` must be the last segment.
# > `<<a::binary, "!">> = "hi!"` can't tell where `a`
# > ends, so it doesn't compile. Give it a size, or
# > match from the other end.
#
# > **Pitfall:** integers are big-endian by default.
# > Formats from x86-land (BMP, WAV, many file
# > headers) are little-endian; read them without
# > `-little` and you get numbers like `65536`
# > instead of `256`, as in the match above.
#
# > **Pitfall:** `byte_size/1` rounds up a bitstring
# > that isn't a whole number of bytes, so a 12-bit
# > value has `byte_size` 2. Use `bit_size/1` when
# > the difference matters.
