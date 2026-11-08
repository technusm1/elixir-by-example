# Across a network, a request that gets no answer is a
# mystery. Either the request was lost and nothing
# happened, or the *reply* was lost and the work was
# done. The caller sees the same timeout either way.
#
# So the caller has two choices, and both are bad on
# their own. Never retry, and some work silently never
# happens (*at most once*). Retry, and some work happens
# twice (*at least once*). The way out is to retry and
# make repeats harmless: the request carries an
# *idempotency key*, and the server remembers which
# keys it has already done.
#
# To show this without real nodes, a `Link` process
# stands between client and server and loses messages
# on cue. It reads a script: deliver, lose the request,
# or deliver the request but lose the reply.
defmodule Link do
  use GenServer

  def start_link(server, script), do: GenServer.start_link(__MODULE__, {server, script})

  @impl true
  def init({server, script}), do: {:ok, {server, script}}

  @impl true
  def handle_call(request, _from, {server, [step | script]}) do
    case step do
      :deliver ->
        {:reply, GenServer.call(server, request), {server, script}}

      :lose_request ->
        {:noreply, {server, script}}

      :lose_reply ->
        _done_but_lost = GenServer.call(server, request)
        {:noreply, {server, script}}
    end
  end
end

# A payment service. `charge/3` without a key just
# charges; with a key it first checks whether that key
# was already charged, and if so returns the first
# result instead of charging again.
defmodule Payments do
  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, nil)
  def charges(server), do: GenServer.call(server, :charges)

  @impl true
  def init(nil), do: {:ok, %{charges: [], seen: %{}}}

  @impl true
  def handle_call({:charge, nil, amount}, _from, state) do
    {:reply, {:ok, :charged}, %{state | charges: state.charges ++ [amount]}}
  end

  def handle_call({:charge, key, amount}, _from, state) do
    case state.seen do
      %{^key => result} ->
        {:reply, result, state}

      _ ->
        result = {:ok, {:charged, key}}

        state = %{
          state
          | charges: state.charges ++ [amount],
            seen: Map.put(state.seen, key, result)
        }

        {:reply, result, state}
    end
  end

  def handle_call(:charges, _from, state), do: {:reply, state.charges, state}
end

# The client: call through the link with a short
# timeout, and retry up to `attempts` times.
defmodule Client do
  def charge(link, amount, key \\ nil, attempts \\ 1) do
    try do
      GenServer.call(link, {:charge, key, amount}, 50)
    catch
      :exit, {:timeout, _} when attempts > 1 ->
        IO.puts("  timeout, retrying")
        charge(link, amount, key, attempts - 1)

      :exit, {:timeout, _} ->
        {:error, :timeout}
    end
  end
end

run = fn title, script, fun ->
  {:ok, payments} = Payments.start_link()
  {:ok, link} = Link.start_link(payments, script)
  IO.puts(title)
  IO.inspect(fun.(link), label: "  client sees")
  IO.inspect(Payments.charges(payments), label: "  charges made")
end

# **Lost request vs. lost reply, no retry.** The client
# sees the same timeout in both cases. In the second
# one, the customer was charged anyway.
run.("lost request", [:lose_request], &Client.charge(&1, 30))
run.("lost reply", [:lose_reply], &Client.charge(&1, 30))

# **Retry without a key.** Retrying after a lost reply
# repeats work that already happened: the customer pays
# twice.
run.("lost reply, retry", [:lose_reply, :deliver], &Client.charge(&1, 30, nil, 3))

# **Retry with an idempotency key.** The second attempt
# finds the key and gets the original result back. One
# charge, and the client learns it went through.
run.(
  "lost reply, retry with a key",
  [:lose_reply, :deliver],
  &Client.charge(&1, 30, "order-1001", 3)
)

# A lost request with a key is also safe: the server
# never saw the key, so the retry does the work once.
run.(
  "lost request, retry with a key",
  [:lose_request, :deliver],
  &Client.charge(&1, 30, "order-1001", 3)
)

# > **Pitfall:** the key belongs to the *operation*, not
# > the attempt. Generate it once ("order 1001, first
# > payment") and send the same key on every retry. A
# > fresh key per attempt protects against nothing.
#
# > **Pitfall:** the server has to remember keys at
# > least as long as a client might retry, and the
# > memory has to survive restarts, or a retry after a
# > crash charges again. In practice the keys live in
# > the database, with a unique index, written in the
# > same transaction as the work (see
# > [The Outbox Pattern](/reliability/outbox)).
#
# > **Pitfall:** between two connected nodes, Erlang
# > delivers messages in order and never twice. That
# > guarantee ends when the connection drops: messages
# > in flight are lost, and nothing tells the sender
# > which ones. Retries are how you get the work done,
# > and idempotency is what makes them safe.
#
# Since OTP 24, `GenServer.call/3` uses a process
# *alias* for the reply, and the alias is deactivated
# when the call times out. A reply that arrives late is
# dropped, so a timed-out call doesn't leave a stray
# message in the caller's mailbox:
{:ok, slow} = Agent.start_link(fn -> nil end)

try do
  Agent.get(slow, fn _ -> Process.sleep(100) end, 50)
catch
  :exit, {:timeout, _} -> IO.puts("call timed out")
end

Process.sleep(100)
IO.inspect(Process.info(self(), :messages), label: "after the late reply")
