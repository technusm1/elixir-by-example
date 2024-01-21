---
title: "Stream and Enum modules"
---
{% contentfor sidebar %}
- **Stream**:  An amount of something or a number of things coming in a continuous flow. ***For example***: a constant stream of enquiries; this new service has created a new stream of revenue for the company.

- **Enumerate**: Mention a number of things one by one. More formally, it can mean: "establish the number of". ***For example***: 6,079 residents were enumerated in 241 establishments.
{% endcontentfor %}
Elixir provides `Stream` and `Enum` modules out of the box for working with enumerables. Enumerables can be lists, maps, ranges or any other type that implements the `Enumerable` protocol. Enumerables can be enumerated in an eager manner (using `Enum` module), or lazily / on-demand (using `Stream` module).

Here we'll learn about the `Enum` module first.

```elixir
# Let's take a list of 10 numbers. Since a list is an
# Enumerable, so we can use Enum and Stream modules.
numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

## The Basics
Functions that need to check the entire enumerable will definitely be in `Enum` module. Such functions include, but are not limited to:
- `all?`, `any?`, `empty?`
- `random`
- `count`, `sum`, `product`, `min`, `max`
- `reverse`, `sort`, `shuffle`

```elixir
# Check if all numbers are greater than 0 (returns true)
numbers |> Enum.all?(fn number -> number > 0 end)
# OR (we can use this shorthand form)
numbers |> Enum.all?(&(&1 > 0))

# Check if all numbers are multiples of 2 (returns false)
numbers |> Enum.all?(&(rem(&1, 2) == 0))

numbers |> Enum.sum # => 55
numbers |> Enum.count # => 10
numbers |> Enum.product # => 3628800
numbers |> Enum.min # => 1
numbers |> Enum.max # => 10
```

## Sorting
Which module will contain the functions related to sorting? `Enum` module, because sorting functions need to process the entire enumerable to generate their results.
```elixir
numbers |> Enum.sort # => Default sorting
numbers |> Enum.sort(:desc) # => Descending order (:desc)
# Give a comparison function that takes two numbers
# and returns a boolean
numbers |> Enum.sort(&(&1 >= &2))
```

