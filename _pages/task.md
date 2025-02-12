---
title: "Task"
---

{% contentfor sidebar %}
Tasks are processes meant to execute a one-off piece of code, generally with no communication with other processes and return a result. They're perfect for concurrent, isolated computations.
{% endcontentfor %}

## What's Cool About Tasks

- **Simple Concurrency**: Run code in parallel without managing processes directly
- **Built-in Error Handling**: Tasks can be supervised and restarted if they fail
- **Async/Await Pattern**: Familiar async programming model for concurrent operations
- **Automatic Process Cleanup**: No need to manually manage process lifecycles
- **Integration with OTP**: Part of OTP, works well with other OTP components

Here's a taste of Tasks in action:

```elixir
# Simple async computation
task = Task.async(fn -> 
  :timer.sleep(1000)
  "Done!"
end)
result = Task.await(task)  # Waits for result: "Done!"

# Multiple concurrent tasks
results = 1..3
|> Enum.map(fn x -> 
  Task.async(fn -> x * 2 end)
end)
|> Enum.map(&Task.await/1)  # [2, 4, 6]
```

## Tasks vs Regular Processes

While you could use `spawn` for one-off processes, Tasks offer several advantages:

✅ **Benefits of Tasks:**
- Built-in timeout handling
- Automatic process linking
- Integration with supervision trees
- Easy error propagation
- Clean async/await interface

```elixir
# Using spawn (basic process)
pid = spawn(fn -> 
  result = expensive_operation()
  send(caller, result)
end)

# Using Task (better approach)
task = Task.async(fn -> expensive_operation() end)
result = Task.await(task, :timer.seconds(5))  # With timeout
```

## Common Task Patterns

### Async/Await

Perfect for parallel computations where you need the results:

```elixir
# Process multiple items concurrently
def process_items(items) do
  items
  |> Enum.map(&Task.async(fn -> process_item(&1) end))
  |> Enum.map(&Task.await/1)
end

# Real-world example
urls
|> Enum.map(&Task.async(fn -> HTTPoison.get!(&1) end))
|> Enum.map(&Task.await(&1, :timer.seconds(5)))
```

### Fire-and-Forget

When you don't need the result:

```elixir
# Start task without waiting
Task.start(fn ->
  Logger.info("Processing in background...")
  expensive_operation()
end)

# Supervised fire-and-forget
Task.Supervisor.start_child(MySupervisor, fn ->
  background_job()
end)
```

### Task Supervision

For better error handling and restart strategies:

```elixir
# In your application supervisor
children = [
  {Task.Supervisor, name: MyApp.TaskSupervisor}
]

# Starting supervised tasks
Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn ->
  might_fail()
end)
```

## Advanced Task Patterns

### Handling Task Results with Timeouts

```elixir
# Using Task.yield to handle timeouts gracefully
task = Task.async(fn -> 
  :timer.sleep(2000)
  {:ok, "Slow operation complete"}
end)

case Task.yield(task, 1000) do
  nil ->
    Task.shutdown(task)
    {:error, :timeout}
  {:ok, result} ->
    result
end
```

### Parallel Map with Chunking

```elixir
defmodule ParallelProcessor do
  def parallel_map(collection, func, chunk_size \\ 1000) do
    collection
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(fn chunk ->
      Task.async(fn -> 
        Enum.map(chunk, func)
      end)
    end)
    |> Task.await_many(:timer.seconds(30))
    |> List.flatten()
  end
end

# Usage example:
1..10_000
|> ParallelProcessor.parallel_map(&expensive_operation/1)
```

### Task Pipeline Pattern

```elixir
defmodule TaskPipeline do
  def process_data(input) do
    input
    |> Task.async(fn -> stage_1() end)
    |> Task.await()
    |> then(&Task.async(fn -> stage_2(&1) end))
    |> Task.await()
    |> then(&Task.async(fn -> stage_3(&1) end))
    |> Task.await()
  end
  
  defp stage_1(data), do: # ... implementation
  defp stage_2(data), do: # ... implementation
  defp stage_3(data), do: # ... implementation
end
```

### Real-World Examples

```elixir
# Parallel API requests with rate limiting
defmodule ApiClient do
  def fetch_all_users(user_ids) do
    user_ids
    |> Stream.chunk_every(10)  # Process 10 at a time
    |> Stream.map(fn chunk ->
      # Start tasks for each chunk
      chunk
      |> Enum.map(&Task.async(fn -> fetch_user(&1) end))
      |> Task.await_many(:timer.seconds(5))
    end)
    |> Enum.to_list()
    |> List.flatten()
  end
  
  defp fetch_user(id) do
    :timer.sleep(100)  # Simulate API call
    %{id: id, name: "User #{id}"}
  end
end

# Background job processing with error handling
defmodule BackgroundJob do
  def process_async(jobs) do
    supervisor = MyApp.TaskSupervisor
    
    jobs
    |> Enum.map(fn job ->
      Task.Supervisor.async_nolink(supervisor, fn ->
        try do
          process_job(job)
        rescue
          e ->
            Logger.error("Job failed: #{inspect(e)}")
            {:error, job, e}
        end
      end)
    end)
    |> Enum.map(fn task ->
      case Task.yield(task, :timer.seconds(10)) || Task.shutdown(task) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
      end
    end)
  end
end
```

## Performance Considerations

- **Memory Usage**: Each task creates a new process, which typically uses 2-3KB of memory
- **CPU Utilization**: Number of concurrent tasks should generally not exceed available CPU cores for CPU-bound work
- **I/O Operations**: For I/O bound operations (like HTTP requests), you can run many more concurrent tasks

```elixir
# Example of controlling concurrency
defmodule ConcurrencyControl do
  @max_concurrency System.schedulers_online() * 2
  
  def parallel_process(items) do
    items
    |> Task.async_stream(
      &process_item/1,
      max_concurrency: @max_concurrency,
      timeout: 5000
    )
    |> Enum.to_list()
  end
end
```

## Best Practices

✅ **Do:**
- Use tasks for independent, concurrent operations
- Set appropriate timeouts for `Task.await`
- Supervise tasks that might fail
- Use `Task.yield_many` for handling multiple tasks with timeouts

❌ **Don't:**
- Use tasks for long-running processes (use GenServer instead)
- Forget to handle task timeouts
- Create too many tasks at once (could overwhelm system)
- Use tasks when you need process state (use GenServer)

## Common Pitfalls & Solutions

- **Task Timeout Issues**
  - 💡 Always set explicit timeouts with `Task.await`
  - 💡 Use `Task.yield` for more control over timeout handling
  - 💡 Consider chunking large numbers of tasks

- **Error Handling**
  - 💡 Use supervised tasks for important operations
  - 💡 Implement proper error handling in task functions
  - 💡 Consider using `Task.async_nolink` to prevent error propagation

## When to Use Tasks

✅ **Great for:**
- Parallel data processing
- Concurrent API calls
- Background job processing
- One-off computations
- Fan-out operations

❌ **Consider alternatives for:**
- Long-running processes (use GenServer)
- Stateful operations (use GenServer)
- Complex process communication (use GenServer)
- Streaming data (use GenStage/Flow)

## Getting Started

Try this simple example in `iex`:

```elixir
# Start an async computation
iex> task = Task.async(fn -> 
  :timer.sleep(1000)
  "Hello from task!"
end)

# Do other work while task runs...
iex> "Working..."

# Get the result
iex> Task.await(task)
"Hello from task!"
```
