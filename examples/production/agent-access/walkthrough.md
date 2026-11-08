Coding agents such as Claude Code and Codex are good at the first hour of an
incident: reading stack traces, comparing state with code, forming and
checking hypotheses. Giving one access to a production node is tempting. The
obvious ways to do it are the dangerous ones:

- **The cookie, `remote` or `rpc`** give *full* control of the node: they run
  any code, including code that deletes data or leaks secrets. An agent can
  make mistakes, and it can be steered by text it reads (a log line or a
  database row written by an attacker can contain instructions: *prompt
  injection*). Whatever it can do, an attacker who controls its input can
  try to make it do.
- **A shared admin login** makes every action unattributable and impossible
  to revoke for one agent alone.

So the agent gets its own narrow door, designed like any other API:

1. **Observe, don't act.** Only read-only commands you wrote and reviewed:
   queues, memory, what a process is doing, bounded traces. Fixes go through
   the normal pipeline (pull request, CI, deploy), and emergency changes are
   made by a human.
2. **Its own credential.** One key per agent, revocable on its own, never the
   cookie.
3. **Audit everything.** Every request, allowed or refused, is logged before
   it runs.
4. **Bound every command.** Fixed result sizes, timeouts, no unbounded traces
   or full-state dumps.
5. **Assume what it reads is hostile and sensitive.** Output can contain
   injected instructions and personal data; return summaries, not raw state,
   and redact secrets.
6. **Keep it off the internet.** Bind it to an internal address, or reach it
   through `kubectl port-forward` or a bastion.

This page builds such a door with OTP's own `:ssh`, inside the release: an SSH
daemon with no shell that runs only an allowlist of commands for the keys it
trusts. Then it plays out an incident: a worker is stuck, and the agent finds
where, without being able to change anything.

## The project

An `orders` app with one worker that charges orders one at a time. Today its
payment provider hangs.

```file mix.exs
```

```file lib/orders/application.ex
```

```file lib/orders/worker.ex
```

The agent's door. `exec: {:direct, fun}` sends every command an SSH client runs
to our function, together with the authenticated user name, and `shell:
:disabled` means there is no interactive shell to fall back on. Commands
outside the allowlist get an error.

```file lib/orders/agent_access.ex
```

```file config/runtime.exs
```

## Set it up

Build the release, then create keys: a host key for the node, so the agent can
verify it's talking to the real thing, and a key pair for the agent, whose
public half goes into `authorized_keys`. The agent pins the node's host key in
its own `known_hosts`.

```sh
MIX_ENV=prod mix release --quiet
mkdir -p ssh/host ssh/agent log
ssh-keygen -q -t ed25519 -N "" -f ssh/host/ssh_host_ed25519_key
ssh-keygen -q -t ed25519 -N "" -C agent -f agent_key
cp agent_key.pub ssh/agent/authorized_keys
echo "[127.0.0.1]:47022 $(cat ssh/host/ssh_host_ed25519_key.pub)" > known_hosts
```

Start the node, and wait until the `orders` application (and with it the
SSH daemon) has started. `agent` is the command the coding agent is allowed to
run: plain `ssh` with its own key and the pinned host key.

```sh
export RELEASE_NODE=orders_demo AGENT_SSH_PORT=47022
export AGENT_SSH_HOST_KEYS="$PWD/ssh/host" AGENT_SSH_AUTHORIZED_KEYS="$PWD/ssh/agent"
export AGENT_AUDIT_LOG="$PWD/log/audit.log"
orders() { _build/prod/rel/orders/bin/orders "$@"; }
orders daemon
until orders rpc 'true = List.keymember?(Application.started_applications(), :orders, 0)' > /dev/null 2>&1; do
  sleep 0.1
done

agent() { ssh -q -p 47022 -i agent_key -o UserKnownHostsFile=known_hosts agent@127.0.0.1 "$@"; }
```

## The incident

100 orders arrive while the payment provider hangs. (An operator runs this
with full access; the agent never could.)

```file incident.exs
```

```sh
orders rpc 'Code.eval_file("incident.exs")'
```

## The agent investigates

It starts with what it may do, then looks for a backlog, then asks the busy
process what it's doing.

```sh
agent help
agent queues
agent where Orders.Worker
```

The answer is complete enough to act on: one order is stuck inside
`call_payment_provider/1`, which has no timeout, and 99 more wait behind it.
The agent can now propose the fix (a timeout on the provider call) as a pull
request.

What it can't do is anything else, such as charging an order itself:

```sh fails
agent 'Orders.Worker.charge(101)'
```

Every request is in the audit log, the refused one included.

```sh
cat log/audit.log
```

Stop the node, and wait until it's gone (it frees its SSH port on the way
out).

```sh
orders stop
while orders pid > /dev/null 2>&1; do sleep 0.1; done
```

> **Pitfall:** an allowlisted command is still code running in production.
> `where` here only accepts names of existing processes
> (`String.to_existing_atom/1`), so the agent can't make the node create atoms,
> and every command returns a bounded amount of text. Review new commands as
> carefully as a public API.

> **Pitfall:** don't add a generic "eval" command, even read-only-looking ones
> like "inspect any process state". State holds secrets and personal data, and
> an eval is the cookie by another name.

> **Pitfall:** `ssh -o StrictHostKeyChecking=no` is the usual shortcut in
> scripts, and it lets anyone who can intercept the connection impersonate
> the node. Pin the host key, as above.

> **Pitfall:** the same rules apply to MCP servers and other agent tools that
> wrap production access: a tool that can run arbitrary commands is the
> cookie, whatever its name.

**Go deeper:** chapter 17 of [The BEAM Book](https://blog.stenmans.org/theBeamBook/#CH-Ops) by Erik Stenman,
"Operation and Maintenance", covers the ways to connect to a running system.
