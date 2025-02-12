---
title: "Agent"
---

{% contentfor sidebar %}
Agents are simple wrappers around state. They provide a basic mechanism to store and retrieve values through a process, making them perfect for managing shared state across your application.
{% endcontentfor %}

## What's Cool About Agents

- **Simple State Management**: Store and retrieve state without complex process code
- **Thread-Safe**: All operations are atomic and synchronized
- **Lightweight**: Minimal overhead compared to GenServer
- **Easy to Use**: Simple API with get/update operations
- **OTP Compliant**: Can be supervised and integrated into supervision trees

Here's a taste of Agents in action:

```elixir
# Start an agent with initial state
{:ok, counter} = Agent.start_link(fn -> 0 end)

# Update state
Agent.update(counter, fn count -> count + 1 end)

# Get current value
current = Agent.get(counter, fn count -> count end)  # Returns 1
```

## Agents vs GenServer

While GenServer offers more features, Agents are perfect for simpler state management:

✅ **Benefits of Agents:**
- Simpler API for state management
- Less boilerplate code
- Perfect for single-purpose state holders
- Built-in synchronization

```elixir
# GenServer approach
defmodule Counter do
  use GenServer
  
  def init(initial), do: {:ok, initial}
  def handle_call(:get, _from, state), do: {:reply, state, state}
  def handle_cast({:increment}, state), do: {:noreply, state + 1}
end

# Agent approach (simpler!)
{:ok, counter} = Agent.start_link(fn -> 0 end)
Agent.update(counter, fn state -> state + 1 end)
Agent.get(counter, fn state -> state end)
```

## Common Agent Patterns

### Basic State Management

```elixir
defmodule UserPreferences do
  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end
  
  def get_preference(key) do
    Agent.get(__MODULE__, fn prefs -> Map.get(prefs, key) end)
  end
  
  def set_preference(key, value) do
    Agent.update(__MODULE__, fn prefs -> 
      Map.put(prefs, key, value)
    end)
  end
end
```

### Atomic Updates

```elixir
defmodule AtomicCounter do
  def start_link do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end
  
  def increment do
    Agent.get_and_update(__MODULE__, fn count ->
      {count + 1, count + 1}
    end)
  end
  
  def current do
    Agent.get(__MODULE__, & &1)
  end
end
```

### Caching Layer

```elixir
defmodule Cache do
  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end
  
  def get(key) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, key) do
        nil -> {:miss, nil}
        value -> {:hit, value}
      end
    end)
  end
  
  def put(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end
  
  def clear do
    Agent.update(__MODULE__, fn _state -> %{} end)
  end
end
```

## Best Practices

✅ **Do:**
- Use Agents for simple state storage
- Keep operations fast and simple
- Name your Agents for easy access
- Use in supervision trees

❌ **Don't:**
- Store large amounts of data
- Perform complex calculations in Agent functions
- Use for state that needs complex synchronization
- Block the Agent with long-running operations

## Common Patterns & Solutions

### Initialization with Supervision

```elixir
defmodule MyApp.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      {Agent, fn -> initial_state() end, name: MyApp.StateAgent}
    ]
    
    opts = [strategy: :one_for_one]
    Supervisor.start_link(children, opts)
  end
  
  defp initial_state, do: %{}
end
```

### Error Handling

```elixir
defmodule SafeAgent do
  def get_value(agent, key) do
    try do
      Agent.get(agent, fn state ->
        Map.get(state, key)
      end)
    catch
      :exit, _ -> {:error, :agent_down}
    end
  end
  
  def update_safely(agent, key, value) do
    try do
      Agent.update(agent, fn state ->
        Map.put(state, key, value)
      end)
    catch
      :exit, _ -> {:error, :agent_down}
    end
  end
end
```

## When to Use Agents

✅ **Great for:**
- Simple key-value storage
- Counters and accumulators
- Configuration storage
- Small caches
- Shared application state

❌ **Consider alternatives for:**
- Complex state management (use GenServer)
- Large data structures (use ETS or database)
- Operations requiring complex logic
- When you need multiple synchronous operations

## Performance Considerations

- **Memory Usage**: Keep state small and focused
- **Operation Speed**: Keep functions passed to Agent simple
- **Concurrency**: All operations are serialized

```elixir
# Bad: Complex computation inside Agent
Agent.get(agent, fn state ->
  Enum.reduce(state, 0, fn {_k, v}, acc ->
    acc + complex_calculation(v)
  end)
end)

# Good: Get data and process outside
data = Agent.get(agent, fn state -> state end)
Enum.reduce(data, 0, fn {_k, v}, acc ->
  acc + complex_calculation(v)
end)
```

## Getting Started

Try this simple example in `iex`:

```elixir
# Start an Agent to store a shopping cart
iex> {:ok, cart} = Agent.start_link(fn -> [] end)

# Add items
iex> Agent.update(cart, fn items -> items ++ ["milk"] end)
:ok
iex> Agent.update(cart, fn items -> items ++ ["bread"] end)
:ok

# Check contents
iex> Agent.get(cart, fn items -> items end)
["milk", "bread"]
```
