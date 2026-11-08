# Simulates the incident: 100 orders arrive while the payment provider hangs.
for id <- 1..100, do: Orders.Worker.charge(id)

# Wait until the first order is stuck and the other 99 are queued behind it.
worker = Process.whereis(Orders.Worker)

wait = fn again ->
  if Process.info(worker, :message_queue_len) == {:message_queue_len, 99},
    do: :ok,
    else: Process.sleep(10) && again.(again)
end

:ok = wait.(wait)
