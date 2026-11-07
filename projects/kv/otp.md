At the end of the Core chapter, **KV** is a good immutable data structure with
a proper type, validation and many buckets. It also has a hard limit: a value
only lives as long as the variable holding it. Two parts of a program can't
share it, and nothing survives the function that created it.

This chapter turns the store into a small service, the way you would in a real
Elixir system:

1. **Put it in a process.** A GenServer owns the state and serialises access,
   so any number of callers can share it without locks.
2. **Isolate failures.** Each bucket gets its own process under a supervisor,
   found by name through a Registry. A crash in one bucket restarts that
   bucket and touches nothing else.
3. **Make reads fast.** Writes still go through the process, but reads go
   straight to an ETS table, so readers never queue behind writers.
4. **Expire keys.** Timers and messages give keys a time to live, the core of
   any cache.

Along the way you'll see the trade-offs these tools force on you: a single
process is a bottleneck, restarting a process loses its state, and an ETS table
dies with its owner. The Distributed track picks up exactly there: keeping data
when a whole machine goes away.

If you skipped the Core chapter, start with its
[project intro](/core/kv). Each step below still runs on its own.
