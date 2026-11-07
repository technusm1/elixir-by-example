After the Distributed chapter, **KV** replicates its data, catches up new
nodes and forms its cluster with libcluster. But it still runs inside
scripts that start their own nodes. This chapter ships it the way real
services ship:

1. **A release.** KV becomes a Mix project built into a release. Every
   server runs the same build; what differs per server (node name, cookie,
   which nodes to cluster with) comes from environment variables read in
   `config/runtime.exs` at boot.

Coming next in this chapter: putting the release in a container image, and
running a KV cluster on Kubernetes.

## Running these examples

Each step is a small Mix project. Its page shows every file and the shell
commands that build and run it; the commands ran when the site was built, so
the output is real. There is no Run button: browsers can't start programs.

To try one yourself, use **Download project**: the zip holds the project
with the page as its README. Run the commands from the README in the
project's directory. You need Elixir (which brings `mix`) and, for steps with
dependencies, access to Hex.
