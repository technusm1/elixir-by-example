# Run inside the live node: traces the replica's handle_call/3 while one
# put happens, then prints what the replica received and what it returned.
session = :trace.session_create(:debug_put, self(), [])
replica = Process.whereis(KV.Replica)
:trace.process(session, replica, true, [:call])
:trace.function(session, {KV.Replica, :handle_call, 3}, [{:_, [], [{:return_trace}]}], [])

KV.Replica.put("lang", "erlang")

ref = :trace.delivered(session, replica)

receive do
  {:trace_delivered, ^replica, ^ref} -> :ok
end

receive do
  {:trace, ^replica, :call, {_mod, _fun, [message, _from, state]}} ->
    IO.inspect(message, label: "received")
    IO.inspect(state, label: "state before")
end

receive do
  {:trace, ^replica, :return_from, _mfa, {:reply, _reply, new_state}} ->
    IO.inspect(new_state, label: "state after")
end

:trace.session_destroy(session)
