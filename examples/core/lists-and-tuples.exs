# Lists are singly linked. Prepending is O(1);
# appending or indexing is O(n).
list = [1, 2, 3]
IO.inspect([0 | list])
IO.inspect(list ++ [4])
IO.inspect(length(list))

# A list is a head and a tail. `hd/1` and `tl/1` take
# them apart, and so does pattern matching.
IO.inspect(hd(list))
IO.inspect(tl(list))
[head | tail] = list
IO.inspect({head, tail})

# Lists can hold mixed types, and `--` removes the
# first occurrence of each element.
IO.inspect([1, :two, "three"])
IO.inspect([1, 2, 1, 3] -- [1])

# Tuples are fixed-size and stored contiguously, so
# reading by index is O(1). Use them for a known
# number of things, like `{:ok, value}`.
t = {:ok, "data", 3}
IO.inspect(elem(t, 1))
IO.inspect(tuple_size(t))
IO.inspect(put_elem(t, 2, 4))

# Both are immutable: "changing" one returns a copy.
IO.inspect(t)

# Lists of integers that happen to be printable get
# shown as charlists.
IO.inspect([104, 105])
IO.inspect([104, 105], charlists: :as_lists)

# Rule of thumb: a list is for "many of the same
# thing", processed in order. A tuple is a small
# record, matched by position.
{:ok, value} = {:ok, 42}
IO.inspect(value)

# > **Pitfall:** building a list with `acc ++ [x]` in a
# > loop is O(n²). Prepend with `[x | acc]` and call
# > `Enum.reverse/1` once at the end.
#
# > **Pitfall:** `[104, 105]` printing as `~c"hi"` is not
# > a bug or data corruption. It's still a list of
# > integers; pass `charlists: :as_lists` to inspect it
# > as numbers.
