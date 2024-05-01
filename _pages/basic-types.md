---
title: "Basic Types and Arithmetic"
---

{% contentfor sidebar %}

- [Integers](#integers)
- [Floats](#floats)
- [Atoms / Symbols](#atoms-symbols)
- [Special Atoms](#special-atoms)
- [Ranges](#ranges)
- [Lists and Tuples](#lists-and-tuples)
- [Strings and Charlists](#strings-and-charlists)
- [Binaries and Bitstrings](#binaries-and-bitstrings)
  {% endcontentfor %}

## Integers

An integer is a negative or positive whole number, or a number without a fractional / decimal part. For example:

```elixir
# -1, 0, 2, 4, 5 etc. are integers
iex> is_integer(1)
true
iex> is_integer(-3)
true
iex> is_integer(0)
true

# Any number with a fractional / decimal part is not an integer
iex> is_integer(-1.1)
false

# Even if it has a zero fractional / decimal part
iex> is_integer(1.0)
false
```

In Elixir, any arithmetic operation except division between two integers returns an integer. A division between two integers will always return a float.

## Floats

A float is a number with a fractional / decimal part. For example:

```elixir
# 1.2, -2.5 etc. are floats
iex> is_float(1.2)
true
iex> is_float(-2.5)
true
# Even if it has a zero fractional / decimal part, it is a float
iex> is_float(0.0)
true

# Any number without a fractional / decimal part is not a float
iex> is_float(0)
false
iex> is_float(1)
false
iex> is_float(-3)
false
```

In Elixir, any arithmetic operation except division between two floats returns a float.

## Atoms / Symbols

Atoms are constants whose values are their own name. Atoms can be composed of Unicode characters such as letters, numbers, underscore (\_), and @. If the keyword has a character that does not belong to the category above, such as spaces, you can wrap it in quotes (see example below).

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
- `nil` (for representing nil values, or indicates an absence of value)

## Lists and Tuples

Lists and Tuples are both ordered collection of elements. You can create them using the following syntax:

| Example                  | List                                                   | Tuple                                                 |
| ------------------------ | ------------------------------------------------------ | ----------------------------------------------------- |
| A collection of integers | `[1, 2, 3]`                                            | `{1, 2, 3}`                                           |
| A collection of strings  | `["hello", "world"]`                                   | `{"hello", "world"}`                                  |
| An empty collection      | `[]`                                                   | `{}`                                                  |
| A collection of lists    | `[[1, 2, 3], ["hello", "world"]]`                      | `{[1, 2, 3], ["hello", "world"]}`                     |
| A collection of tuples   | `[{1, 2, 3}, {"hello", "world"}]`                      | `{1, 2, 3}, {"hello", "world"}`                       |
| Mixing everything        | `[1, "hello", :world, [1, 2, :hi], {"hello", :world}]` | `{1, "hello", :world, [1, 2, :hi], {"hello", :world}` |

However, both lists and tuples have some differences:

| Differences                                                                                      | List                                                                                                                                                                                                 | Tuple                                                                                                               |
| ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Underlying Implementation                                                                        | Lists are implemented as linked lists internally.                                                                                                                                                    | Tuples are implemented as fixed-size arrays.                                                                        |
| Storage                                                                                          | Elements may be stored in any location.                                                                                                                                                              | Tuple elements are stored in contiguous memory.                                                                     |
| Random Access                                                                                    | Lists don't have random access, however, accessing first element is O(1). For accessing rest of the elements, it is O(n), since we need to traverse each element one by one.                         | Accessing any element of a tuple is O(1).                                                                           |
| Modification (data is immutable in Elixir, read this as creation of new collection from old one) | Prepending an element to a list will create a new list, but its an O(1) operation, because we're putting the element at the head of the list and the existing list becomes the tail of the new list. | Adding an element to a tuple will create a new tuple, which is O(n) operation, since it results in shallow copying. |

Unlike most programming languages, Elixir lists do not support random access, because they are implemented as linked lists instead of arrays.

Tuples are intended as fixed-size containers for multiple elements. To manipulate a collection of elements, use a list instead. A tuple may contain elements of different types, which are stored contiguously in memory. Accessing any element takes constant time, but modifying a tuple, which produces a shallow copy, takes linear time. Tuples are good for reading data while lists are better for traversals.
