# When a service you depend on goes down, calling it
# anyway makes things worse: every caller waits for a
# timeout, and the struggling service gets no room to
# recover. A *circuit breaker* sits in front of it and
# remembers recent failures:
#
# - **closed**: calls go through, failures are counted.
#   Too many in a row and the breaker *opens*.
# - **open**: calls fail at once, without touching the
#   service. After a cooldown the breaker goes
#   *half-open*.
# - **half-open**: one trial call goes through. If it
#   works the breaker closes again; if it fails it
#   opens for another cooldown.
#
# That's a state machine, so it's built on
# [`:gen_statem`](/otp/gen-statem). Three of its
# features do the work:
#
# - `:handle_event_function`: the `:state` query and
#   late reports are handled the same way in every
#   state, so one `handle_event/4` beats a function per
#   state.
# - **enter calls** set each state up, whichever
#   transition led there: entering `:open` starts the
#   cooldown, entering `:closed` or `:half_open` clears
#   the counters.
# - a **state timeout** is the cooldown. It can only
#   fire while the breaker is still open.
#
# The callers run the protected function themselves:
# they `ask` the breaker for permission, then `report`
# how it went. The breaker never waits on the slow
# service.
defmodule Breaker do
  @behaviour :gen_statem

  def start_link(opts), do: :gen_statem.start_link(__MODULE__, opts, [])
  def state(breaker), do: :gen_statem.call(breaker, :state)

  def run(breaker, fun) do
    case :gen_statem.call(breaker, :ask) do
      :go ->
        result = fun.()
        :gen_statem.cast(breaker, {:report, result})
        result

      :reject ->
        {:error, :circuit_open}
    end
  end

  @impl true
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl true
  def init(opts) do
    data = %{failures: 0, threshold: opts[:threshold], cooldown: opts[:cooldown], trial: false}
    {:ok, :closed, data}
  end

  # Entering a state.
  @impl true
  def handle_event(:enter, _previous, :open, data) do
    {:keep_state_and_data, [{:state_timeout, data.cooldown, :cooldown_over}]}
  end

  def handle_event(:enter, _previous, _closed_or_half_open, data) do
    {:keep_state, %{data | failures: 0, trial: false}}
  end

  def handle_event({:call, from}, :state, state, _data) do
    {:keep_state_and_data, [{:reply, from, state}]}
  end

  # Asking for permission.
  def handle_event({:call, from}, :ask, :closed, _data) do
    {:keep_state_and_data, [{:reply, from, :go}]}
  end

  def handle_event({:call, from}, :ask, :open, _data) do
    {:keep_state_and_data, [{:reply, from, :reject}]}
  end

  def handle_event({:call, from}, :ask, :half_open, %{trial: false} = data) do
    {:keep_state, %{data | trial: true}, [{:reply, from, :go}]}
  end

  def handle_event({:call, from}, :ask, :half_open, %{trial: true}) do
    {:keep_state_and_data, [{:reply, from, :reject}]}
  end

  # Results reported back by callers.
  def handle_event(:cast, {:report, {:ok, _}}, :closed, data) do
    {:keep_state, %{data | failures: 0}}
  end

  def handle_event(:cast, {:report, {:error, _}}, :closed, data) do
    failures = data.failures + 1

    if failures >= data.threshold do
      {:next_state, :open, data}
    else
      {:keep_state, %{data | failures: failures}}
    end
  end

  def handle_event(:cast, {:report, {:ok, _}}, :half_open, data) do
    {:next_state, :closed, data}
  end

  def handle_event(:cast, {:report, {:error, _}}, :half_open, data) do
    {:next_state, :open, data}
  end

  # A call that started before the breaker opened can
  # still report afterwards. It changes nothing.
  def handle_event(:cast, {:report, _}, :open, _data), do: :keep_state_and_data

  # The cooldown is over.
  def handle_event(:state_timeout, :cooldown_over, :open, data) do
    {:next_state, :half_open, data}
  end
end

# A pretend service that can be switched up and down,
# and counts how often it was really called.
defmodule Service do
  def start, do: Agent.start_link(fn -> %{up: true, calls: 0} end)
  def set(service, up?), do: Agent.update(service, &%{&1 | up: up?})
  def calls(service), do: Agent.get(service, & &1.calls)

  def request(service) do
    Agent.get_and_update(service, fn s ->
      result = if s.up, do: {:ok, :data}, else: {:error, :service_down}
      {result, %{s | calls: s.calls + 1}}
    end)
  end
end

defmodule Wait do
  def until(check) do
    if check.(), do: :ok, else: Process.sleep(1) && until(check)
  end
end

{:ok, service} = Service.start()
{:ok, breaker} = Breaker.start_link(threshold: 3, cooldown: 100)
call = fn -> Breaker.run(breaker, fn -> Service.request(service) end) end

# While the service is up, the breaker stays out of the
# way.
IO.inspect(call.(), label: "closed")

# The service goes down. Three failures in a row open
# the breaker. (`report` is a cast, but it comes from
# the same caller as the next `ask`, so it always
# arrives first.)
Service.set(service, false)
for _ <- 1..3, do: IO.inspect(call.(), label: "closed")
IO.inspect(Breaker.state(breaker), label: "state")

# Open: callers get an answer at once, and the service
# isn't called at all. Its call count stays at 4.
for _ <- 1..3, do: IO.inspect(call.(), label: "open")
IO.inspect(Service.calls(service), label: "service calls")

# After the cooldown, one trial call. The service is
# still down, so the breaker opens again for another
# cooldown.
Wait.until(fn -> Breaker.state(breaker) == :half_open end)
IO.inspect(call.(), label: "half-open trial")
IO.inspect(Breaker.state(breaker), label: "state")

# The service recovers. The next trial succeeds and the
# breaker closes.
Service.set(service, true)
Wait.until(fn -> Breaker.state(breaker) == :half_open end)
IO.inspect(call.(), label: "half-open trial")
IO.inspect(Breaker.state(breaker), label: "state")
IO.inspect(call.(), label: "closed")

# > **Pitfall:** if the trial caller crashes before it
# > reports, a half-open breaker waits for that report
# > forever and rejects everything. Production breakers
# > monitor the trial caller, or set a state timeout in
# > the `:half_open` enter call too, so a lost trial
# > counts as a failure.
#
# > **Pitfall:** count only failures that say the
# > *dependency* is unhealthy: timeouts, connection
# > errors, 5xx responses. A burst of bad requests from
# > one client (a 404, a validation error) shouldn't cut
# > everyone off.
#
# > **Pitfall:** don't run the protected call *inside*
# > the breaker process. Every caller would then queue
# > behind the slowest call, and the breaker would
# > become the outage it was meant to prevent.
