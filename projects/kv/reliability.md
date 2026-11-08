After the Production chapter, **KV** runs as a release on a cluster, and you
can debug it live. This chapter is about what happens to it on a bad day: one
client that won't stop writing, a burst of traffic bigger than the disk can
take, a replica that hangs instead of failing.

The concept pages of this track are about keeping *data* right when steps fail:
transactions and constraints, the outbox pattern, and sagas. The patterns
these steps use live next to the tools they're built from: rate limiting,
backpressure and the circuit breaker are on the Processes and OTP track.

1. **Limit each client.** A per-client rate limit in ETS keeps one broken
   script from taking the store for itself.
2. **Bound the writes.** Writes go to disk through a bounded buffer. A burst
   makes writers wait instead of filling memory.
3. **Replicate behind a breaker.** A hung replica trips a circuit breaker, so
   writes stop waiting for it, and the replica is caught up when it recovers.

Like the OTP chapter's steps, each one is a single script that runs on its own,
in the browser too.
