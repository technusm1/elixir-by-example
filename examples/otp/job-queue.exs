# A job queue runs work in the background: sending
# email, resizing images, calling webhooks. The parts
# that make it more than `Task.start/1`:
#
# - **bounded concurrency**: at most N jobs run at once,
# - **retries with backoff**: a failed job runs again
#   later, waiting longer after each failure,
# - **dead letters**: a job that keeps failing is set
#   aside for a human, instead of retrying forever.
#
# The pieces are all OTP. A GenServer owns the queue.
# Jobs run as tasks under a `Task.Supervisor` with
# `async_nolink/2`, so a crashing job is a message to
# the queue, not a crash of the queue. Backoff is a
# `Process.send_after/3` to itself.
#
# Jobs crash on purpose below, and each crash would
# print an error report. `Logger.configure/1` silences
# them, so the output shows what the queue decided.
Logger.configure(level: :none)

defmodule JobQueue do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  # A job is an id and a function of the attempt number.
  def enqueue(queue, id, fun), do: GenServer.call(queue, {:enqueue, id, fun})

  # Waits until every job has finished or been given up
  # on, then returns what happened to each.
  def drain(queue), do: GenServer.call(queue, :drain, :infinity)

  @impl true
  def init(opts) do
    state = %{
      tasks: Keyword.fetch!(opts, :tasks),
      max_running: Keyword.get(opts, :max_running, 2),
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      backoff: Keyword.get(opts, :backoff, 10),
      pending: :queue.new(),
      running: %{},
      retrying: 0,
      history: %{},
      dead: [],
      drainers: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, id, fun}, _from, state) do
    state = %{state | pending: :queue.in({id, fun, 1}, state.pending)}
    {:reply, :ok, start_jobs(state)}
  end

  # Deferred reply: answered once the queue is idle.
  def handle_call(:drain, from, state) do
    {:noreply, maybe_idle(%{state | drainers: [from | state.drainers]})}
  end

  # A task finished and returned a value.
  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {job, running} = Map.pop!(state.running, ref)
    {:noreply, %{state | running: running} |> finished(job, result) |> start_jobs()}
  end

  # A task crashed. Its exception arrives as a `:DOWN`.
  def handle_info({:DOWN, ref, :process, _pid, {exception, _stacktrace}}, state) do
    {job, running} = Map.pop!(state.running, ref)
    result = {:error, {:crashed, Exception.message(exception)}}
    {:noreply, %{state | running: running} |> finished(job, result) |> start_jobs()}
  end

  # A backoff timer fired: the job goes back in line.
  def handle_info({:retry, job}, state) do
    state = %{state | pending: :queue.in(job, state.pending), retrying: state.retrying - 1}
    {:noreply, start_jobs(state)}
  end

  defp start_jobs(state) do
    with true <- map_size(state.running) < state.max_running,
         {{:value, {_id, fun, attempt} = job}, pending} <- :queue.out(state.pending) do
      task = Task.Supervisor.async_nolink(state.tasks, fn -> fun.(attempt) end)
      start_jobs(%{state | pending: pending, running: Map.put(state.running, task.ref, job)})
    else
      _ -> maybe_idle(state)
    end
  end

  defp finished(state, {id, _fun, attempt} = job, result) do
    case result do
      {:ok, _} ->
        record(state, id, attempt, result, :done)

      {:error, _} when attempt < state.max_attempts ->
        # Exponential backoff: 10 ms, 20 ms, 40 ms, ...
        delay = state.backoff * Integer.pow(2, attempt - 1)
        Process.send_after(self(), {:retry, put_elem(job, 2, attempt + 1)}, delay)
        state = %{state | retrying: state.retrying + 1}
        record(state, id, attempt, result, {:retry_in_ms, delay})

      {:error, _} ->
        state = %{state | dead: state.dead ++ [id]}
        record(state, id, attempt, result, :dead_letter)
    end
  end

  defp record(state, id, attempt, result, decision) do
    entry = {attempt, result, decision}
    %{state | history: Map.update(state.history, id, [entry], &(&1 ++ [entry]))}
  end

  defp maybe_idle(state) do
    idle? = :queue.is_empty(state.pending) and state.running == %{} and state.retrying == 0

    if idle? and state.drainers != [] do
      for from <- state.drainers, do: GenServer.reply(from, Map.take(state, [:history, :dead]))
      %{state | drainers: []}
    else
      state
    end
  end
end

# The queue and its task supervisor start together under
# one supervisor. `:rest_for_one` restarts the queue if
# the task supervisor dies, since the queue's running
# jobs died with it.
children = [
  {Task.Supervisor, name: Jobs.Tasks},
  {JobQueue, name: Jobs.Queue, tasks: Jobs.Tasks}
]

{:ok, _} = Supervisor.start_link(children, strategy: :rest_for_one)

# Four jobs: one that just works, one that times out
# twice, one that crashes once, and a webhook whose
# endpoint keeps answering 500.
JobQueue.enqueue(Jobs.Queue, :email, fn _ -> {:ok, :sent} end)

JobQueue.enqueue(Jobs.Queue, :report, fn
  attempt when attempt < 3 -> {:error, :timeout}
  _ -> {:ok, :built}
end)

JobQueue.enqueue(Jobs.Queue, :resize, fn
  1 -> raise "corrupt header"
  _ -> {:ok, :resized}
end)

JobQueue.enqueue(Jobs.Queue, :webhook, fn _ -> {:error, :http_500} end)

# Jobs run concurrently, so they finish in no fixed
# order, but each job's own attempts happen one after
# another. The history is printed per job.
%{history: history, dead: dead} = JobQueue.drain(Jobs.Queue)

for id <- [:email, :report, :resize, :webhook] do
  IO.puts("#{id}:")
  for entry <- history[id], do: IO.puts("  " <> inspect(entry))
end

IO.inspect(dead, label: "dead letters")

# The queue lives in a process's memory. If that process
# dies, the supervisor starts a fresh one, and every job
# it was holding is gone. Here a job is enqueued behind a
# long one, and the queue is killed.
JobQueue.enqueue(Jobs.Queue, :slow, fn _ -> Process.sleep(:infinity) end)
JobQueue.enqueue(Jobs.Queue, :invoice, fn _ -> {:ok, :sent} end)
JobQueue.enqueue(Jobs.Queue, :thumbnail, fn _ -> {:ok, :made} end)

old = Process.whereis(Jobs.Queue)
Process.exit(old, :kill)

defmodule Wait do
  def until(check) do
    if check.(), do: :ok, else: Process.sleep(1) && until(check)
  end
end

Wait.until(fn -> Process.whereis(Jobs.Queue) not in [nil, old] end)
IO.inspect(JobQueue.drain(Jobs.Queue), label: "after a restart")

# > **Pitfall:** an in-memory queue loses its jobs on a
# > crash or a deploy. For jobs that must not be lost,
# > keep them in a database. [Oban](https://hexdocs.pm/oban)
# > does exactly that on Postgres or SQLite, with the
# > retries and backoff shown here.
#
# > **Pitfall:** retries mean a job can run more than
# > once: it may have done its work and crashed before
# > reporting. Jobs with side effects (charging a card,
# > sending an email) must be safe to repeat. See
# > [Idempotency and Retries](/distributed/idempotency).
#
# > **Pitfall:** backoff without *jitter* retries all
# > failed jobs at the same moment. When an outage ends,
# > they all hit the recovering service together. Add a
# > random part to each delay in production.
