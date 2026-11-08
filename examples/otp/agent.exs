# An `Agent` is a process that only holds state. You
# pass it functions to read or change that state. It's
# a GenServer (the general-purpose server process,
# next page) with the callbacks written for you.
{:ok, agent} = Agent.start_link(fn -> %{} end)

Agent.update(agent, &Map.put(&1, "apples", 3))
Agent.update(agent, &Map.put(&1, "pears", 5))

IO.inspect(Agent.get(agent, & &1), label: "state")
IO.inspect(Agent.get(agent, &Map.get(&1, "apples")), label: "apples")

# `get_and_update/2` reads and writes atomically:
# nothing else can run between the read and the write.
# Here we pop a key and get its value back.
popped = Agent.get_and_update(agent, &Map.pop(&1, "pears"))
IO.inspect(popped, label: "popped pears")
IO.inspect(Agent.get(agent, & &1), label: "after pop")

# Agents are usually named and wrapped in a module so
# callers don't deal with pids or the state's shape.
# `name: __MODULE__` registers the process under the
# module's name, so calls can use the name instead of
# a pid. `use Agent` adds a `child_spec/1` so a
# supervisor can start it (see
# [Protocols and Behaviours](/core/protocols)).
defmodule Visits do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def hit(page), do: Agent.update(__MODULE__, &Map.update(&1, page, 1, fn n -> n + 1 end))

  def count(page), do: Agent.get(__MODULE__, &Map.get(&1, page, 0))
end

{:ok, _} = Visits.start_link([])
for page <- ["/", "/docs", "/", "/"], do: Visits.hit(page)
IO.inspect(Visits.count("/"), label: "visits to /")

# The function you pass runs *inside* the agent
# process. Concurrent updates are therefore
# serialized: 100 concurrent increments never lose one.
{:ok, counter} = Agent.start_link(fn -> 0 end)

1..100
|> Enum.map(fn _ -> Task.async(fn -> Agent.update(counter, &(&1 + 1)) end) end)
|> Task.await_many()

IO.inspect(Agent.get(counter, & &1), label: "counter")

# > **Pitfall:** read-then-write from the client loses
# > updates: `v = Agent.get(a, & &1); Agent.update(a,
# > fn _ -> v + 1 end)` lets another process sneak in
# > between. Do the whole change inside one
# > `update`/`get_and_update` function.
#
# > **Pitfall:** expensive work inside the function
# > blocks everyone else using the agent. Compute
# > outside, then store the result. Once you need
# > `handle_info`, timeouts, or more than get/update,
# > graduate to a GenServer.
