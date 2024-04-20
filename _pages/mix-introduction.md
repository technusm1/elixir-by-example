---
title: "Introduction to Mix"
---
{% contentfor sidebar %}
`mix` is a tool for managing Elixir projects and their dependencies. As programmers, we carefully **mix** different stuff (i.e. dependencies) to produce amazing **elixirs** (i.e. projects). A good analogy to remember.
{% endcontentfor %}
`mix` tool ships by default with Elixir and it provides **tasks** for creating, compiling, testing, and deploying Elixir projects.

Some tasks are provided out of the box by `mix`. You can also create your own tasks to be run by `mix` using Elixir code. Let's explore some of them.

## Out of the box tasks
- `mix help`: This command lists all tasks and aliases available in `mix` and in your project.
- `mix help <task>`: Prints the documentation for a given task or alias.
- `mix new your_awesome_elixir_project`: Creates a new Elixir project named `your_awesome_elixir_project`. To find out more about this task, type `mix help new`. Get it?
- `mix compile`: Compiles the project.
- `mix run`: Runs the current application. It starts the current application dependencies and then the application itself. The application will be compiled if it has not been compiled yet or it is outdated.
- `mix test`: Runs tests for the project (present in `test` directory in the project).

## Creating your own tasks