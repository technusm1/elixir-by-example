---
title: "GenServer by Example"
---
{% contentfor sidebar %}
GenServer is a behavior module for implementing the server of a client-server relation. It's one of the core building blocks in Elixir/Erlang for creating stateful, concurrent processes that can handle messages reliably.
{% endcontentfor %}

## What's Cool About GenServer

- **Built-in Concurrency**: Each GenServer runs in its own process, handling messages concurrently
- **State Management**: Cleanly manages state without global variables or mutability
- **Fault Tolerance**: Can be supervised and restarted when things go wrong
- **Two-Way Communication**: Supports both synchronous (call) and asynchronous (cast) messages
- **Battle-tested**: Powers many production systems handling millions of users

Here's a quick taste:

```elixir
defmodule Counter do
  use GenServer

  # Client API
  def start_link(initial_count) do
    GenServer.start_link(__MODULE__, initial_count)
  end

  def increment(pid) do
    GenServer.cast(pid, :increment)
  end

  def get_count(pid) do
    GenServer.call(pid, :get_count)
  end

  # Server Callbacks
  @impl true
  def init(count), do: {:ok, count}

  @impl true
  def handle_cast(:increment, count), do: {:noreply, count + 1}

  @impl true
  def handle_call(:get_count, _from, count), do: {:reply, count, count}
end

# Usage:
{:ok, pid} = Counter.start_link(0)
Counter.increment(pid)
Counter.get_count(pid)  # Returns 1
```

## Common Patterns & Solutions

### State Management
- **Challenge**: Keeping track of complex state
- 💡 Use structs for complex state
- 💡 Update state immutably
- 💡 Keep state minimal and focused

```elixir
defmodule ShoppingCart do
  use GenServer
  
  defstruct items: %{}, total: 0
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{})
  end
  
  def add_item(pid, item, price) do
    GenServer.cast(pid, {:add_item, item, price})
  end
  
  @impl true
  def handle_cast({:add_item, item, price}, state) do
    new_items = Map.put(state.items, item, price)
    new_total = state.total + price
    {:noreply, %{state | items: new_items, total: new_total}}
  end
end
```

### Message Handling
- **Challenge**: Deciding between sync and async messages
- 💡 Use `call` for operations needing a response
- 💡 Use `cast` for fire-and-forget operations
- 💡 Use `handle_info` for unexpected or timer messages

```elixir
defmodule CacheServer do
  use GenServer

  # Synchronous - waits for response
  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end

  # Asynchronous - doesn't wait
  def set(pid, key, value) do
    GenServer.cast(pid, {:set, key, value})
  end

  # Timer message
  def schedule_cleanup(pid) do
    Process.send_after(pid, :cleanup, :timer.hours(1))
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  @impl true
  def handle_cast({:set, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end

  @impl true
  def handle_info(:cleanup, state) do
    schedule_cleanup(self())
    {:noreply, %{}}
  end
end
```

### Error Handling
- **Challenge**: Dealing with crashes and errors
- 💡 Use supervisors for automatic restarts
- 💡 Implement `terminate/2` for cleanup
- 💡 Return `:stop` tuple for controlled shutdowns

```elixir
defmodule ResilientWorker do
  use GenServer

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @impl true
  def handle_call(:risky_work, _from, state) do
    case do_work() do
      {:ok, result} -> {:reply, result, state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Terminating due to #{inspect(reason)}")
    cleanup(state)
    :ok
  end
end
```

## When to Use GenServer

✅ **Great for:**
- Managing shared state (e.g., counters, caches)
- Long-running processes (e.g., connection pools)
- Rate limiting and throttling
- Background job processing
- Stateful game servers

❌ **Consider alternatives for:**
- Simple data transformations (use regular modules)
- One-off async tasks (use Task)
- Pure functions (use regular modules)
- Complex event handling (use GenStateMachine)

## Advanced Patterns

### Periodic Work

```elixir
defmodule PeriodicWorker do
  use GenServer
  
  @interval :timer.seconds(60)
  
  def init(state) do
    schedule_work()
    {:ok, state}
  end
  
  def handle_info(:work, state) do
    do_work(state)
    schedule_work()
    {:noreply, state}
  end
  
  defp schedule_work do
    Process.send_after(self(), :work, @interval)
  end
end
```

### State Machines

```elixir
defmodule TrafficLight do
  use GenServer
  
  @states [:red, :yellow, :green]
  
  def next_state(pid), do: GenServer.cast(pid, :next)
  
  @impl true
  def handle_cast(:next, state) do
    next = Enum.at(@states, rem(Enum.find_index(@states, &(&1 == state)) + 1, 3))
    {:noreply, next}
  end
end
```

### Rate Limiting

```elixir
defmodule RateLimiter do
  use GenServer

  defstruct requests: %{}, limit: 0, window: 0

  # Client API
  def start_link(opts) do
    limit = Keyword.get(opts, :limit, 10)
    window = Keyword.get(opts, :window, :timer.seconds(1))
    GenServer.start_link(__MODULE__, {limit, window})
  end

  def check_rate(pid, key) do
    GenServer.call(pid, {:check_rate, key})
  end

  # Server Callbacks
  @impl true
  def init({limit, window}) do
    {:ok, %__MODULE__{limit: limit, window: window}}
  end

  @impl true
  def handle_call({:check_rate, key}, _from, state) do
    now = System.system_time(:millisecond)
    window_start = now - state.window
    
    # Get existing requests and filter out old ones
    requests = Map.get(state.requests, key, [])
    valid_requests = Enum.filter(requests, &(&1 >= window_start))
    
    cond do
      length(valid_requests) < state.limit ->
        # Under limit - allow request
        new_requests = [now | valid_requests]
        new_state = put_in(state.requests[key], new_requests)
        {:reply, :ok, new_state}
      true ->
        # Over limit - deny request
        {:reply, {:error, :rate_limited}, state}
    end
  end
end

# Usage Example:
{:ok, limiter} = RateLimiter.start_link(limit: 2, window: :timer.seconds(5))

# First two requests succeed
:ok = RateLimiter.check_rate(limiter, "user_1")
:ok = RateLimiter.check_rate(limiter, "user_1")

# Third request fails (within 5 second window)
{:error, :rate_limited} = RateLimiter.check_rate(limiter, "user_1")

# Different user has their own limit
:ok = RateLimiter.check_rate(limiter, "user_2")
```

This rate limiter:
- Tracks requests per key (e.g., user ID, IP address)
- Allows configurable number of requests (`limit`) within a time window
- Automatically cleans up old requests
- Is suitable for rate limiting API endpoints or user actions

## Getting Started

The easiest way to experiment with GenServer is in `iex`:

```elixir
iex> defmodule Echo do
...>   use GenServer
...>   def init(state), do: {:ok, state}
...>   def handle_call(:ping, _from, state) do
...>     {:reply, :pong, state}
...>   end
...> end

iex> {:ok, pid} = GenServer.start_link(Echo, [])
iex> GenServer.call(pid, :ping)
:pong
```

Remember: GenServer is powerful, but with great power comes great responsibility. Start simple and add complexity only when needed!
