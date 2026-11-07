# In step 4 one process served every bucket. Now each
# bucket is its own process: a crash in one bucket
# can't touch the others, and buckets work in parallel.
# Buckets are created on demand under a
# DynamicSupervisor, and found by name in a Registry.
#
# Crash reports contain pids that change every run, so
# we silence the logger for this demo.
Logger.configure(level: :none)

defmodule KV.Bucket do
  use Agent, restart: :permanent

  def start_link(name), do: Agent.start_link(fn -> %{} end, name: via(name))
  def via(name), do: {:via, Registry, {KV.Registry, name}}

  def put(name, k, v), do: Agent.update(via(name), &Map.put(&1, k, v))
  def get(name, k), do: Agent.get(via(name), &Map.get(&1, k))
end

defmodule KV do
  # Look the bucket up; start it if it doesn't exist.
  # If two callers race to create the same bucket, the
  # Registry lets only one win and the other gets
  # `:already_started`, which is fine.
  def bucket(name) do
    case DynamicSupervisor.start_child(KV.BucketSup, {KV.Bucket, name}) do
      {:ok, _} -> name
      {:error, {:already_started, _}} -> name
    end
  end
end

# The tree: a Registry first (buckets need it to
# register), then the DynamicSupervisor that owns the
# buckets. Order matters: children start top to bottom.
children = [
  {Registry, keys: :unique, name: KV.Registry},
  {DynamicSupervisor, name: KV.BucketSup, strategy: :one_for_one}
]

{:ok, _} = Supervisor.start_link(children, strategy: :rest_for_one)

KV.bucket("users") |> KV.Bucket.put("ada", :admin)
KV.bucket("carts") |> KV.Bucket.put("ada", ["book"])
IO.inspect(KV.Bucket.get("users", "ada"), label: "users/ada")
IO.inspect(DynamicSupervisor.count_children(KV.BucketSup).active, label: "buckets")

# Crash the "carts" bucket. We kill it outright, as a
# bug or out-of-memory would. Monitoring it tells us
# when it's really gone.
[{carts_pid, _}] = Registry.lookup(KV.Registry, "carts")
ref = Process.monitor(carts_pid)
Process.exit(carts_pid, :kill)
receive do: ({:DOWN, ^ref, _, _, _} -> :ok)

# The supervisor restarts it under the same name, but
# with *empty* state. "users" never noticed.
_ = DynamicSupervisor.which_children(KV.BucketSup)
IO.inspect(KV.Bucket.get("carts", "ada"), label: "carts/ada after crash")
IO.inspect(KV.Bucket.get("users", "ada"), label: "users/ada untouched")

# Isolation worked, but every read still queues
# behind writes in the bucket's mailbox. Step 6 keeps
# writes in a process but moves reads to ETS, so
# readers never wait. (Surviving crashes with data
# intact needs persistence or replication; that comes
# with the Distributed track.)
