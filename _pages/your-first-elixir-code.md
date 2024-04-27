---
title: "Your First Elixir Code"
---

{% contentfor sidebar %}
Go ahead and have a look the [installation instructions](https://elixir-lang.org/install.html) for setting up Elixir. Once you're done, come back to this page.
{% endcontentfor %}

## Our First Elixir Program

Dating back to the 1970s, the first program for learners trying out a new programming language has been to print the text `Hello, world!` on screen.

Let's try the same for Elixir. Let's see different ways to do it.

## Scripting mode

Go ahead and type the following code in an IDE / Text Editor of your choice.

```elixir
IO.puts("Hello, world!")
```

Save the file as `hello_world.exs`.

To run the program, type the following command in your terminal / command prompt:

```sh
elixir hello_world.exs
```

The file type `.exs` indicates that it's an Elixir script. You should see the following output printed on screen:

```
Hello, world!
```

## Compilation

Elixir can be both compiled and interpreted. Compiled code is faster than interpreted code, and it can be run on the BEAM VM, which is what we'll be working with in the coming lessons.

For compiling the code, we'll write it in `.ex` files, which indicates to the elixir compiler that the file contains source code for an Elixir
program that will be compiled to be run on the BEAM VM.

Let's write some code and compile it:

```elixir
defmodule HelloWorld do
  def hello do
    IO.puts("Hello, world!")
  end
end
```

Save the file as `hello_world_123.ex`. Now change to the directory where the file is saved and compile the file with the following command:

```sh
# Compile the file to be run on the BEAM VM
elixirc hello_world.ex
```

We should see a new file named `Elixir.HelloWorld.beam` in the same directory. This file contains the compiled bytecode for the program, which can be executed on the BEAM VM. If you've used languages like Java, this is similar
