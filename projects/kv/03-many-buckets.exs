# One flat namespace gets crowded. Step 3 groups keys
# into named *buckets* (a map of maps) and adds a
# protocol so the store can be exported to a simple
# text format without KV knowing every value type.
defmodule KV do
  defstruct buckets: %{}

  # `Map.update/4` inserts a new bucket holding the
  # default, or runs the function on the existing one.
  def put(%KV{} = kv, bucket, key, value) do
    %{kv | buckets: Map.update(kv.buckets, bucket, %{key => value}, &Map.put(&1, key, value))}
  end

  def get(%KV{buckets: b}, bucket, key), do: b |> Map.get(bucket, %{}) |> Map.get(key)

  def bucket_names(%KV{buckets: b}), do: b |> Map.keys() |> Enum.sort()

  # Bulk loading is a reduce: fold every row into the
  # store, starting from an empty one.
  def load(rows), do: Enum.reduce(rows, %KV{}, fn {b, k, v}, kv -> put(kv, b, k, v) end)
end

# A protocol is an interface dispatched on the data
# type. Anyone can implement it for their own types,
# later, without touching KV. `Enum.map_join/3` maps
# each item and joins the results with a separator.
defprotocol KV.Codec do
  @doc "Encodes a value as a single line of text."
  def encode(value)
end

defimpl KV.Codec, for: BitString do
  def encode(s), do: inspect(s)
end

defimpl KV.Codec, for: Integer do
  def encode(n), do: Integer.to_string(n)
end

defimpl KV.Codec, for: List do
  def encode(list), do: "[" <> Enum.map_join(list, ",", &KV.Codec.encode/1) <> "]"
end

rows = [
  {"users", "ada", "admin"},
  {"users", "grace", "editor"},
  {"stats", "visits", 42},
  {"stats", "top", ["/", "/docs"]}
]

kv = KV.load(rows)
IO.inspect(KV.bucket_names(kv), label: "buckets")
IO.inspect(KV.get(kv, "users", "grace"), label: "users/grace")
IO.inspect(KV.get(kv, "nope", "x"), label: "missing bucket")

# Export with an Enum pipeline: flatten buckets into
# rows, sort them, encode each value via the protocol.
# `Enum.flat_map/2` maps each bucket to a list of rows
# and concatenates the lists.
kv.buckets
|> Enum.flat_map(fn {bucket, data} -> Enum.map(data, fn {k, v} -> {bucket, k, v} end) end)
|> Enum.sort()
|> Enum.map(fn {b, k, v} -> "#{b}/#{k} = #{KV.Codec.encode(v)}" end)
|> Enum.each(&IO.puts/1)

# Values without an implementation fail loudly, which
# is better than writing something unreadable. The
# exception's `value` field holds the offending value.
try do
  KV.Codec.encode(%{a: 1})
rescue
  e in Protocol.UndefinedError -> IO.puts("no codec for #{inspect(e.value)}")
end

# Still a value in a variable: one process owns it,
# nobody else can see updates. Step 4 (OTP track)
# moves the store into a process everyone can call.
