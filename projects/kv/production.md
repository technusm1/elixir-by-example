After the Deployment chapter, **KV** ships as a release, runs in containers
and forms clusters on Kubernetes. Now it's in production, and things go wrong
there that never went wrong on a laptop. This chapter is about finding and
fixing them on the running system, with the tools the BEAM ships with.

1. **Debug it live.** A KV node ignores updates. Reproduce the report with
   `rpc`, look at the replica's state, trace one update to find the bug, and
   hot-patch the fix into the running node without losing its data.

## Running these examples

Like the Deployment chapter, each step is a small Mix project whose commands
ran when the site was built. Use **Download project** to get it with the page
as its README.
