---
title: "Stream and Enum modules"
---
{% contentfor sidebar %}
- **Stream**:  An amount of something or a number of things coming in a continuous flow. ***For example***: a constant stream of enquiries; this new service has created a new stream of revenue for the company.

- **Enumerate**: Mention a number of things one by one. More formally, it can mean: "establish the number of". ***For example***: 6,079 residents were enumerated in 241 establishments.
{% endcontentfor %}
Elixir provides `Stream` and `Enum` modules out of the box for working with collections. Collections can be enumerated in an eager manner (using `Enum` module), or lazily / on-demand (using `Stream` module).

```elixir
# Let's take a list of 10 numbers. Since a list is an
# Enumerable, so we can use Enum and Stream modules.
numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

```elixir
# Check if all numbers are greater than 0 (returns true)
numbers |> Enum.all?(fn number -> number > 0 end)
# OR (shorthand form)
numbers |> Enum.all?(&(&1 > 0))

# Check if all numbers are multiples of 2 (returns false)
numbers |> Enum.all?(&(rem(&1, 2) == 0))
```

What will you do to check if any one of the numbers is a multiple of 2?