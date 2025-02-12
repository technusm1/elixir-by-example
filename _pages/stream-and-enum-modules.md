---
title: "Stream and Enum modules"
---
{% contentfor sidebar %}
- **Stream**: An amount of something or a number of things coming in a continuous flow. ***For example***: a constant stream of enquiries; this new service has created a new stream of revenue for the company.

- **Enumerate**: Mention a number of things one by one. More formally, it can mean: "establish the number of". ***For example***: 6,079 residents were enumerated in 241 establishments.
{% endcontentfor %}

In many programming languages, we use loops to process collections of data. Elixir takes a different approach - instead of loops, it provides powerful `Stream` and `Enum` modules for working with collections (called enumerables). Enumerables can be lists, maps, ranges, or any other type that implements the `Enumerable` protocol.

You can process enumerables in two ways:
- Eagerly (using `Enum` module) - processes the entire collection at once
- Lazily (using `Stream` module) - processes items only when needed

## Choosing Between Stream and Enum

When working with Elixir's collection functions, you can use this mental model to decide which module to use:

### Enum Module Functions
- Need to process the entire collection immediately
- Return a final result (like `sum`, `count`, `max`)
- Transform a collection into another collection all at once
- Need to sort, reverse, or shuffle (requires seeing all elements)

### Stream Module Functions
- Want to defer processing until needed
- Building a pipeline of transformations
- Working with infinite or very large collections
- Need memory efficiency over immediate results
- Composing operations that might not all be needed

### Quick Decision Guide
Ask yourself these questions:
1. "Do I need to see all elements to get the result?"
   - `sort` needs all elements → `Enum`
   - `map` can work one element at a time → available in both
   
2. "Am I building a pipeline of operations?"
   - Just one operation → `Enum` is simpler
   - Multiple operations → Consider `Stream` for efficiency

3. "What's the size of my data?"
   - Small collection → `Enum` is fine
   - Large/Infinite collection → `Stream` is better

```elixir
# Example: When to use Enum
# Here we need the entire list to get max
numbers |> Enum.max()

# Example: When to use Stream
# Here we can process one item at a time
1..1_000_000
|> Stream.map(&(&1 * 2))
|> Stream.filter(&(&1 > 100))
|> Enum.take(5)  # Only now do we process elements, and only until we get 5
```

### Common Functions Available in Both Modules
These operations can work one element at a time:
- `map/2`
- `filter/2`
- `take/2`
- `drop/2`
- `with_index/1`

### Functions Only in Enum
These need to see all elements:
- `sort/1,2`
- `reverse/1`
- `shuffle/1`
- `uniq/1`
- `count/1`
- `sum/1`
- `min/1`, `max/1`

## Basic Operations

Let's start with some common operations using a simple list:

```elixir
numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

### Checking Collections
The `Enum` module provides simple functions to inspect collections:

```elixir
# Check conditions
numbers |> Enum.all?(&(&1 > 0))    # true - all positive?
numbers |> Enum.any?(&(&1 > 9))    # true - any greater than 9?
numbers |> Enum.empty?             # false - is list empty?

# Basic calculations
numbers |> Enum.count             # => 10
numbers |> Enum.sum               # => 55
numbers |> Enum.min               # => 1
numbers |> Enum.max               # => 10
```

### Sorting and Ordering
```elixir
# Basic sorting
numbers |> Enum.sort                    # Ascending (default)
numbers |> Enum.sort(:desc)             # Descending
numbers |> Enum.sort(&(&1 >= &2))       # Custom comparison

# Get first/last elements
numbers |> Enum.take(3)                 # => [1, 2, 3]
numbers |> Enum.take(-2)                # => [9, 10]
numbers |> Enum.drop(7)                 # => [8, 9, 10]

# Random operations
numbers |> Enum.random                  # Get random element
numbers |> Enum.shuffle                 # Random order
```

## Common Transformations

### Transforming Each Element
In other languages, you might use a for-loop to transform each element. In Elixir:

```elixir
# Double each number
numbers |> Enum.map(fn num -> num * 2 end)
# => [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]

# Shorter syntax using capture operator (&)
numbers |> Enum.map(&(&1 * 2))

# Convert numbers to strings
numbers |> Enum.map(&Integer.to_string/1)
# => ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
```

### Filtering Elements
```elixir
# Get even numbers
numbers |> Enum.filter(fn num -> rem(num, 2) == 0 end)
# => [2, 4, 6, 8, 10]

# Get numbers greater than 5
numbers |> Enum.filter(&(&1 > 5))
# => [6, 7, 8, 9, 10]
```

### Reducing/Accumulating Values
```elixir
# Sum all numbers (though Enum.sum/1 is better for this specific case)
numbers |> Enum.reduce(0, fn num, acc -> acc + num end)
# => 55

# Build a string like "1-2-3-4-5-6-7-8-9-10"
numbers |> Enum.reduce("", fn
  num, "" -> Integer.to_string(num)
  num, acc -> acc <> "-" <> Integer.to_string(num)
end)
```

## Advanced Operations

### Generating Sequences with unfold
`Enum.unfold/2` generates a sequence from a starting value:

```elixir
# Generate Fibonacci sequence
Enum.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end) |> Enum.take(10)
# => [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]

# Generate powers of 2
Enum.unfold(1, fn n -> {n, n * 2} end) |> Enum.take(5)
# => [1, 2, 4, 8, 16]
```

### Lazy Processing with Stream
Stream allows you to build a pipeline of operations that are executed only when needed:

```elixir
# This creates a stream but doesn't process anything yet
stream = 1..1_000_000
|> Stream.map(&(&1 * 2))
|> Stream.filter(&(rem(&1, 4) == 0))

# Now we take just the first 5 elements - only these are processed
stream |> Enum.take(5)
# => [4, 8, 12, 16, 20]

# Create an infinite stream of random numbers between 1 and 100
Stream.repeatedly(fn -> :rand.uniform(100) end)
|> Enum.take(5)
# => [45, 67, 23, 89, 12] (random numbers)

# Create a cycle of elements
Stream.cycle(["A", "B", "C"])
|> Enum.take(5)
# => ["A", "B", "C", "A", "B"]
```

### Working with Multiple Collections
```elixir
# Zip two lists together
Enum.zip([1, 2, 3], [:a, :b, :c])
# => [{1, :a}, {2, :b}, {3, :c}]

# Combine elements with a custom function
Enum.zip_with([1, 2, 3], [4, 5, 6], fn x, y -> x * y end)
# => [4, 10, 18]

# Group elements by a function
users = [
  %{name: "John", role: "admin"},
  %{name: "Jane", role: "user"},
  %{name: "Bob", role: "admin"}
]
Enum.group_by(users, &(&1.role), &(&1.name))
# => %{"admin" => ["John", "Bob"], "user" => ["Jane"]}
```

### Chunking and Sliding Windows
```elixir
# Split into chunks of 3
Enum.chunk_every(1..10, 3)
# => [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]

# Sliding window of size 2
Enum.chunk_every(1..5, 2, 1, :discard)
# => [[1, 2], [2, 3], [3, 4], [4, 5]]

# Split when element changes
[1, 1, 2, 2, 2, 3, 4, 4, 1]
|> Enum.chunk_by(&(&1))
# => [[1, 1], [2, 2, 2], [3], [4, 4], [1]]
```

## Real World Examples

### Processing User Data
```elixir
users = [
  %{name: "John", age: 30, active: true},
  %{name: "Jane", age: 25, active: false},
  %{name: "Bob", age: 35, active: true}
]

# Get names of active users over 28
users
|> Stream.filter(fn user -> user.active end)
|> Stream.filter(fn user -> user.age > 28 end)
|> Stream.map(fn user -> user.name end)
|> Enum.to_list()
# => ["John", "Bob"]
```

### Building HTML Lists
```elixir
["Home", "About", "Contact"]
|> Enum.map(fn text -> "<li>#{text}</li>" end)
|> Enum.join("\n")
# => "<li>Home</li>\n<li>About</li>\n<li>Contact</li>"
```

### Working with Ranges
```elixir
# Generate multiplication table for 5
1..10
|> Stream.map(fn n -> "5 x #{n} = #{5 * n}" end)
|> Enum.to_list()
# => ["5 x 1 = 5", "5 x 2 = 10", ...]

# Generate pairs for tournament matches
teams = ["Red", "Blue", "Green", "Yellow"]
for team1 <- teams,
    team2 <- teams,
    team1 < team2,
    do: {team1, team2}
# => [{"Red", "Blue"}, {"Red", "Green"}, ...]
```

```elixir
# Let's take a list of 10 numbers. Since a list is an
# Enumerable, so we can use Enum and Stream modules.
numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```