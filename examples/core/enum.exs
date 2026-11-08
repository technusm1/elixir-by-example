# `Enum` is the toolbox for anything *enumerable*:
# lists, maps, ranges, MapSets (sets of unique
# values) and more. Its functions
# are eager: each one walks the whole collection and
# returns a new list (or a single value).
numbers = [5, 3, 8, 1, 9, 2]

IO.inspect(Enum.map(numbers, fn n -> n * 10 end), label: "map")
IO.inspect(Enum.filter(numbers, &(&1 > 4)), label: "filter")
IO.inspect(Enum.reject(numbers, &(&1 > 4)), label: "reject")

# `&(&1 > 4)` is the capture shorthand for
# `fn x -> x > 4 end`. `&String.upcase/1` captures a
# named function.
IO.inspect(Enum.map(["a", "b"], &String.upcase/1), label: "capture")

# Reducing a collection to one value.
IO.inspect(Enum.sum(numbers), label: "sum")
IO.inspect(Enum.max(numbers), label: "max")
IO.inspect(Enum.reduce(numbers, 0, fn n, acc -> acc + n * n end), label: "sum of squares")

# Sorting, with a key function or a direction.
words = ["pear", "fig", "banana", "kiwi"]
IO.inspect(Enum.sort(words), label: "sort")
IO.inspect(Enum.sort_by(words, &String.length/1), label: "by length")
IO.inspect(Enum.sort(numbers, :desc), label: "desc")

# Grouping and counting are one call each.
# `~w(a b a)` is shorthand for the list of words
# `["a", "b", "a"]`.
IO.inspect(Enum.group_by(words, &String.length/1), label: "group_by")
IO.inspect(Enum.frequencies(~w(a b a c a b)), label: "frequencies")

# Maps enumerate as `{key, value}` tuples, and
# `Map.new/2` or `Enum.into/2` turns them back into a
# map.
prices = %{apple: 3, pear: 5}
doubled = Map.new(prices, fn {fruit, price} -> {fruit, price * 2} end)
IO.inspect(doubled, label: "doubled")

# Ranges are enumerable too, and `Enum.with_index/1`,
# `Enum.zip/2` and `Enum.chunk_every/2` cover most
# "loop with a counter" needs.
IO.inspect(Enum.to_list(1..5), label: "range")
IO.inspect(Enum.with_index(["a", "b", "c"]), label: "with_index")
IO.inspect(Enum.zip([1, 2, 3], [:x, :y, :z]), label: "zip")
IO.inspect(Enum.chunk_every(1..7, 3), label: "chunks")

# `Enum.find/2` and `Enum.any?/2` stop at the first
# match instead of walking everything.
IO.inspect(Enum.find(numbers, &(&1 > 7)), label: "find")
IO.inspect(Enum.any?(numbers, &(&1 < 0)), label: "any negative?")

# > **Pitfall:** each `Enum` call builds a full
# > intermediate list. Chaining `map |> filter |> take(5)`
# > over a million items does all the work before
# > `take/2` runs. For large or infinite inputs, use
# > `Stream` and finish with one `Enum` call.
#
# > **Pitfall:** the last chunk above printed as
# > `~c"\a"`. That *is* `[7]`: a list of integers that
# > are all printable codepoints is shown as a charlist.
# > The data is fine; only the display differs. Pass
# > `charlists: :as_lists` to `IO.inspect/2` to see
# > plain numbers:
IO.inspect([7, 8, 9], charlists: :as_lists)

# > **Pitfall:** `Enum.map/2` on a map returns a
# > *list* of tuples, not a map. Use `Map.new/2` (as
# > above) when you want a map back.
