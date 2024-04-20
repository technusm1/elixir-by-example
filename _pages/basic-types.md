---
title: "Basic Types and Arithmetic"
---
{% contentfor sidebar %}
- [Integers](#integers)
- [Floats](#floats)
- [Atoms / Symbols](#atoms-symbols)
- [Special Atoms](#special-atoms)
- [Lists](#lists)
- [Tuples](#tuples)
- [Strings and Charlists](#strings-and-charlists)
- [Binaries and Bitstrings](#binaries-and-bitstrings)
{% endcontentfor %}

## Integers
An integer is a negative or positive whole number, or a number without a fractional / decimal part. For example: -1, 0, 2, 5 etc. are integers, but -1.2, -2.4, 4.8 etc. are not integers. In Elixir, any arithmetic operation except division between two integers returns an integer. A division between two integers will always return a float.

## Floats
A float is any real number with a fractional / decimal part. This part may or may not be 0. For example: 1.5, 2.4, -1.6 etc. are floats. 2.0, 3.0 etc. are floats, but 2, 3 etc. are not, they are integers. In Elixir, any arithmetic operation except division between two floats returns a float.

## Atoms / Symbols
Atoms are constants whose values are their own name. Atoms can be composed of Unicode characters such as letters, numbers, underscore (_), and @. If the keyword has a character that does not belong to the category above, such as spaces, you can wrap it in quotes (see example below).

```elixir
iex> :hello_world
:hello_world
iex> :"this is an atom with spaces"
:"this is an atom with spaces"
```

Two atoms are equal if their names are equal.

> 🤔 **SOMETHING TO REMEMBER**: `:hello` and `:"hello"` are the same atom. Hence they are both equal.

## Special Atoms
There are certain atoms in Elixir that hold a special meaning. They are:
- `true` (used for representing truthy values)
- `false` (used for representing false values)
- `nil` (for representing nil values)
