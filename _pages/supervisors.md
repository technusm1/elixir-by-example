---
title: "Supervisors"
---

{% contentfor sidebar %}
Supervisors are processes that monitor other processes (called child processes) and restart them when they crash. They're the foundation of Elixir's fault-tolerance and self-healing capabilities.
{% endcontentfor %}

## What's Cool About Supervisors

- **Automatic Process Recovery**: Restarts crashed processes automatically
- **Hierarchical Structure**: Build supervision trees for complex applications
- **Flexible Strategies**: Different ways to handle process failures
- **Process Dependencies**: Manage startup and shutdown order
- **Zero Downtime**: Keep your application running even when things go wrong

<iframe width="560" height="315" src="https://www.youtube.com/embed/cG8iwK_6KIg" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

This creative video explains supervision strategies using the classic game Doom! It's a fun way to understand how different supervisor strategies work in practice.

## Supervision Strategies

### one_for_one
When a child process crashes, only that process is restarted.

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Cache, []},
      {TaskProcessor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### one_for_all
When a child crashes, all other children are terminated and restarted.

```elixir
# Use when all children are interdependent
children = [
  {DatabaseConnection, []},
  {CacheLayer, []},
  {WebServer, []}
]

Supervisor.init(children, strategy: :one_for_all)
```

### rest_for_one
When a child crashes, only that child and the children that started after it are restarted.

```elixir
# Order matters! Later processes depend on earlier ones
children = [
  {Config, []},      # If this crashes, all restart
  {Database, []},    # If this crashes, WebServer restarts too
  {WebServer, []}    # If this crashes, only it restarts
]

Supervisor.init(children, strategy: :rest_for_one)
```

## Dynamic vs Static Supervisors

### Static Supervisor
For a fixed number of children known at startup:

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      {Cache, []},
      {WebServer, port: 4000},
      {TaskQueue, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Dynamic Supervisor
For children that are started and stopped dynamically:

```elixir
defmodule MyApp.WorkerSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_worker(args) do
    spec = {Worker, args}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
```

## Advanced Supervision Patterns

### Supervision Trees

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Top-level supervisor
      {MyApp.MainSupervisor, []},
      
      # Dynamic supervisor for workers
      {MyApp.WorkerSupervisor, []},
      
      # Supervisor for web-related processes
      {MyApp.Web.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Temporary vs Permanent Children

```elixir
# Permanent child (default) - always restarted
child_spec = %{
  id: Worker,
  start: {Worker, :start_link, []},
  restart: :permanent
}

# Temporary child - never restarted
temp_spec = %{
  id: TempWorker,
  start: {TempWorker, :start_link, []},
  restart: :temporary
}

# Transient child - restarted only on abnormal termination
transient_spec = %{
  id: TransientWorker,
  start: {TransientWorker, :start_link, []},
  restart: :transient
}
```

## Best Practices

✅ **Do:**
- Use supervision trees to organize your application
- Choose appropriate restart strategies
- Set reasonable restart frequency limits
- Document dependencies between processes

❌ **Don't:**
- Over-nest supervisors unnecessarily
- Mix different failure domains under the same supervisor
- Ignore supervisor restart intensity
- Put unrelated processes under the same supervisor

## Common Patterns & Solutions

### Rate Limiting Restarts

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def init(_init_arg) do
    children = [
      {Worker, []}
    ]

    # Max 3 restarts in 5 seconds
    Supervisor.init(children, 
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end
end
```

### Graceful Shutdown

```elixir
children = [
  %{
    id: Worker,
    start: {Worker, :start_link, []},
    shutdown: 10_000  # Give 10 seconds for cleanup
  }
]
```

## When to Use Different Strategies

✅ **one_for_one when:**
- Processes are independent
- Failures should be isolated
- Example: Multiple web handlers

✅ **one_for_all when:**
- Processes are tightly coupled
- All processes need consistent state
- Example: Database connection pool

✅ **rest_for_one when:**
- Processes have a clear dependency chain
- Later processes depend on earlier ones
- Example: Config → Database → WebServer

## Performance Considerations

- **Restart Speed**: Keep child initialization fast
- **Memory Usage**: Each supervisor has overhead
- **Process Links**: Many links can impact message passing
- **Restart Frequency**: Set appropriate limits

## Getting Started

Try this simple example in `iex`:

```elixir
# Define a simple worker
defmodule Worker do
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id)
  end

  def init(id) do
    {:ok, id}
  end
end

# Start a dynamic supervisor
{:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

# Start some children
DynamicSupervisor.start_child(sup, {Worker, 1})
DynamicSupervisor.start_child(sup, {Worker, 2})

# Check supervisor status
DynamicSupervisor.count_children(sup)
```
