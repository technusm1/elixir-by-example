Concept pages show one idea at a time. Real programs combine them, so each
track ends with a project that does exactly that. Across the whole site we
build one program and keep growing it: **KV**, a small key-value store.

## Why a key-value store?

It's the smallest program that touches everything Elixir is good at. A store
needs a data structure and an API (this track), then has to be shared by many
callers at once and survive crashes (the OTP track), and finally has to live
on more than one machine (the Distributed track, coming next). Caches, session
stores, rate limiters and service registries are all KV stores underneath.

## What changes along the way

| Track | The store is… | You'll use |
| --- | --- | --- |
| **Core Elixir** (this chapter) | an immutable value passed around by functions | maps, modules, structs, `with`, protocols |
| **Processes and OTP** | a supervised process, with fast reads and expiring keys | GenServer, supervisors, Registry, ETS, timers |
| **Distributed Elixir** *(coming next)* | replicated across nodes | nodes, `:pg`, partitions, Mnesia |

## How the steps work

Each step is one runnable file that stands on its own: it redefines what it
needs instead of importing earlier steps, so you can open any step and run it.
Every step says what changed since the last one and which problem the next
one solves. The concept pages each step builds on are linked at the top.
