# Step 1's store was a bare map, so nothing stopped a
# caller from passing *any* map, or storing keys we
# never meant to allow. This step gives KV its own
# type: a struct with validation at the boundary.
#
# A struct is a map with a fixed set of fields and a
# name. `@enforce_keys` makes construction without
# those fields a compile-time error.
defmodule KV do
  @enforce_keys [:data, :max_keys]
  defstruct [:data, :max_keys]

  # `@type` names a type for docs and tools (see
  # [Typespecs and Types](/core/typespecs)).
  @type key :: String.t()
  @type t :: %__MODULE__{data: %{key() => term()}, max_keys: pos_integer()}

  @spec new(pos_integer()) :: t()
  def new(max_keys \\ 100) when is_integer(max_keys) and max_keys > 0 do
    %KV{data: %{}, max_keys: max_keys}
  end

  # `put/3` validates, then writes. Each check returns
  # `:ok` or `{:error, reason}`; `with` runs them in
  # order and stops at the first one that doesn't match.
  # `%KV{} = kv` accepts only a KV and binds all of it.
  @spec put(t(), key(), term()) :: {:ok, t()} | {:error, atom()}
  def put(%KV{} = kv, key, value) do
    with :ok <- check_key(key),
         :ok <- check_room(kv, key) do
      {:ok, %{kv | data: Map.put(kv.data, key, value)}}
    end
  end

  @spec fetch(t(), key()) :: {:ok, term()} | {:error, :not_found}
  def fetch(%KV{data: data}, key) do
    case Map.fetch(data, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :not_found}
    end
  end

  defp check_key(key) when is_binary(key) and byte_size(key) in 1..64, do: :ok
  defp check_key(_), do: {:error, :invalid_key}

  defp check_room(%KV{data: data, max_keys: max}, key) do
    if map_size(data) < max or Map.has_key?(data, key), do: :ok, else: {:error, :full}
  end
end

# The happy path chains with `with` too. Each step
# hands the new store to the next.
{:ok, kv} =
  with {:ok, kv} <- KV.put(KV.new(2), "lang", "elixir"),
       {:ok, kv} <- KV.put(kv, "vm", "beam") do
    {:ok, kv}
  end

IO.inspect(KV.fetch(kv, "lang"), label: "fetch lang")
IO.inspect(KV.fetch(kv, "nope"), label: "fetch nope")

# Failures come back as values the caller can match
# on, not exceptions.
IO.inspect(KV.put(kv, :lang, "x"), label: "atom key")
IO.inspect(KV.put(kv, "year", 2012), label: "third key")
IO.inspect(KV.put(kv, "vm", "BEAM") |> elem(0), label: "overwrite")

# Pattern matching on `%KV{}` in function heads means
# a plain map is rejected immediately, with a clear
# error naming the function.
try do
  KV.put(%{}, "k", "v")
rescue
  e in FunctionClauseError -> IO.puts("rejected: " <> Exception.message(e))
end

# Most stores need more than one namespace: users,
# sessions, settings. Step 3 adds named buckets.
