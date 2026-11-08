# A node's memory keeps growing, but no process holds
# anything big. Two BEAM rules explain most of these
# mysteries, and both follow from how processes stay
# isolated: every process has its own heap, and a message
# is *copied* into the receiver's heap.
#
# 1. Copying flattens terms. A term that shares parts
#    with itself is copied once per reference, so it can
#    grow on the way.
# 2. Big binaries are the exception: they live outside
#    the process heaps and are shared by reference. A
#    small slice of a big binary can keep all of it alive.
#
# Sizes here are in *words* (8 bytes on a 64-bit system,
# 4 in the browser's runtime),
# as reported by `:erts_debug`, a module meant for
# exploring the runtime like this, not for production
# code. Small integers and atoms take no space of their
# own: they fit inside the word that refers to them. (A
# float takes a header word plus 8 bytes, which is 2 words
# on a 64-bit system and 3 in the browser's 32-bit one.)
for term <- [42, :ok, {1, 2}, [1, 2, 3], %{a: 1}] do
  IO.puts("#{inspect(term)}: #{:erts_debug.flat_size(term)} words")
end

# Rule 1. A tuple holding the same 1000-element list twice
# stores the list once: `size/1` counts shared parts once,
# `flat_size/1` counts them every time they appear.
list = Enum.to_list(1..1000)
pair = {list, list}
IO.inspect(:erts_debug.size(pair), label: "pair, as stored")
IO.inspect(:erts_debug.flat_size(pair), label: "pair, flattened")

# Sending it copies it into the receiver's heap, and the
# copy is flat: the receiver ends up with twice the data.
me = self()

receiver =
  spawn(fn ->
    receive do
      term -> send(me, {:size, :erts_debug.size(term)})
    end
  end)

send(receiver, pair)
receive do: ({:size, words} -> IO.inspect(words, label: "pair, after sending"))

# Rule 2. Binaries over 64 bytes are stored once, outside
# any process, and passed around by reference, so sending
# one is cheap. A slice of one is a reference too, into
# the original. `:binary.referenced_byte_size/1` reports
# how many bytes a binary keeps alive.
payload = :binary.copy("x", 1_000_000)

for n <- [10, 64, 65, 1000] do
  slice = binary_part(payload, 0, n)
  IO.puts("slice of #{n} bytes keeps #{:binary.referenced_byte_size(slice)} bytes alive")
end

# Slices up to 64 bytes are copied, so they don't hold on
# to the original; bigger ones do. `:binary.copy/1` makes
# an independent copy of exactly the slice.
slice = binary_part(payload, 0, 1000)
IO.inspect(:binary.referenced_byte_size(:binary.copy(slice)), label: "copied slice keeps")

# > **Pitfall:** keeping a slice of a large request body,
# > file or message (an id, a header) in a GenServer's
# > state or in ETS keeps the *whole* original in memory.
# > Copy slices you keep for long with `:binary.copy/1`.
#
# > **Pitfall:** a large binary is freed only when every
# > process that referenced it has garbage-collected. A
# > long-lived process that rarely does work (a registry,
# > a cache owner) can hold many dead binaries. Hibernating
# > it (`{:noreply, state, :hibernate}`) or calling
# > `:erlang.garbage_collect/1` lets them go.
#
# > **Pitfall:** sending a big, internally shared term (a
# > tree built from repeated subtrees, a list referenced
# > from many places) multiplies its size in transit, and
# > the same goes for storing it in ETS. Measure with
# > `:erts_debug.flat_size/1` before sending big terms.
#
# **Go deeper:** [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Processes) by Erik
# Stenman explains how a process is laid out in memory
# (chapter 3), how terms and binaries are represented
# ([chapter 4](https://blog.stenmans.org/theBeamBook/#CH-TypeSystem)), and how the per-process
# garbage collector works
# ([chapter 12](https://blog.stenmans.org/theBeamBook/#CH-GC)).
