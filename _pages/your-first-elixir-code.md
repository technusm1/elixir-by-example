---
title: "Your First Elixir Code"
---
{% contentfor sidebar %}
Go ahead and have a look the [installation instructions](https://elixir-lang.org/install.html) for setting up Elixir. Once you're done, come back to this page.
{% endcontentfor %}

## Our First Elixir Program
Dating back to the 1970s, the first program for learners trying out a new programming language has been to print the text `Hello, world!` on screen.

Let's try the same for Elixir. Go ahead and type the following code in an IDE / Text Editor of your choice.

```elixir
IO.puts("Hello, world!")
```

Save the file as `hello_world.exs`.

To run the program, type `elixir hello_world.exs` in the terminal / command prompt. The file type `.exs` indicates that it's an Elixir script, to be run line-by-line by `elixir` interpreter.

You should see the text `Hello, world!` printed on screen.

We can also compile Elixir code (in fact that's how we'll be working mostly). For this, we'll work with another file type: `.ex` files, which indicates that the file contains source code for an Elixir program that will be compiled to be run on the BEAM VM.