defmodule Ebe.Catalog do
  @moduledoc """
  The single source of truth for what the site contains and in which order.

  Every entry maps to a file under `examples/<track>/<slug>.exs` (concept pages)
  or `projects/<project>/<slug>.exs` (project steps), or to a directory in the
  same place holding a multi-file project and its `walkthrough.md` (see
  `Ebe.Walkthrough`). Everything here is checked at compile time:

    * every referenced file must exist (and is tracked as an external resource,
      so editing the catalog or adding files triggers recompilation),
    * slugs must be unique within a track,
    * every concept a project step `uses:` must be a real example slug,
    * every `no_run:` reason must be a non-empty string.

  `no_run:` disables the in-browser Run button and becomes its tooltip. CI also
  verifies that every example *without* `no_run:` runs in Popcorn with output
  matching the real BEAM, so this list cannot silently rot.
  """

  alias Ebe.Catalog.{Entry, Track}

  @root Path.expand("../..", __DIR__)

  @no_dist "Needs several connected nodes. Browsers can't open the network sockets " <>
             "Erlang distribution uses, so this one runs on the native BEAM only."

  @no_os "Starts operating-system programs, which a browser tab can't do, " <>
           "so this one runs on the native BEAM only."

  @no_tools "Uses OTP's profiling tools (the `tools` application), which the " <>
              "in-browser runtime doesn't include, so this one runs on the native BEAM only."

  @tracks [
    %{
      id: "core",
      title: "Core Elixir",
      blurb: "The language itself: data, pattern matching, functions, modules and protocols.",
      examples: [
        {"hello-world", "Hello World"},
        {"values", "Values"},
        {"atoms", "Atoms"},
        {"strings", "Strings"},
        {"binaries", "Binaries and Bitstrings"},
        {"lists-and-tuples", "Lists and Tuples"},
        {"maps", "Maps"},
        {"keyword-lists", "Keyword Lists"},
        {"pattern-matching", "Pattern Matching"},
        {"case-cond-if", "case, cond and if"},
        {"functions", "Anonymous Functions"},
        {"modules", "Modules and Named Functions"},
        {"guards", "Guards"},
        {"recursion", "Recursion"},
        {"pipe-operator", "The Pipe Operator"},
        {"enum", "Enum"},
        {"comprehensions", "Comprehensions"},
        {"streams", "Streams"},
        {"erlang-data-structures", "Erlang Data Structures"},
        {"structs", "Structs"},
        {"typespecs", "Typespecs and Types"},
        {"protocols", "Protocols"},
        {"with", "with"},
        {"errors", "Errors and Tagged Tuples"},
        {"sigils", "Sigils"},
        {"compilation", "From Source to BEAM"},
        {"mix", "Mix Projects"}
      ],
      project:
        {"kv", "Build a key-value store",
         [
           {"01-a-map-is-a-store", "A map is already a store", uses: ["maps", "modules"]},
           {"02-a-proper-type", "Give it a proper type", uses: ["structs", "with", "errors"]},
           {"03-many-buckets", "Many buckets", uses: ["enum", "pipe-operator", "protocols"]}
         ]}
    },
    %{
      id: "otp",
      title: "Processes and OTP",
      blurb: "Concurrency the BEAM way: lightweight processes, messages, and supervision.",
      examples: [
        {"processes", "Processes"},
        {"messages", "Sending and Receiving Messages"},
        {"links-and-monitors", "Links and Monitors"},
        {"task", "Task"},
        {"agent", "Agent"},
        {"genserver", "GenServer"},
        {"gen-statem", ":gen_statem"},
        {"backpressure", "Backpressure"},
        {"supervisors", "Supervisors"},
        {"job-queue", "Job Queue"},
        {"registry", "Registry"},
        {"ets", "ETS"},
        {"caching", "Caching"},
        {"rate-limiting", "Rate Limiting"},
        {"circuit-breaker", "Circuit Breaker"},
        {"process-dictionary", "The Process Dictionary"},
        {"ports-and-nifs", "Ports and NIFs", no_run: @no_os}
      ],
      project:
        {"kv", "Make the store concurrent",
         [
           {"04-a-store-process", "The store becomes a process", uses: ["genserver"]},
           {"05-supervised-buckets", "Supervised buckets", uses: ["supervisors", "registry"]},
           {"06-fast-reads-with-ets", "Fast reads with ETS", uses: ["ets", "genserver"]},
           {"07-expiring-keys", "Expiring keys", uses: ["messages", "genserver"]}
         ]}
    },
    %{
      id: "distributed",
      title: "Distributed Elixir",
      blurb: "Many machines, one system: connected nodes, cluster-wide names and process groups.",
      examples: [
        {"nodes", "Nodes and Distribution",
         args: ["--name", "nodes@127.0.0.1"], no_run: @no_dist},
        {"global", "Global Names with :global",
         args: ["--name", "global@127.0.0.1"], no_run: @no_dist},
        {"pg", "Process Groups with :pg", args: ["--name", "pg@127.0.0.1"], no_run: @no_dist},
        {"partitions", "Partitions and Split Brain", no_run: @no_dist},
        {"leases", "Leases and Fencing Tokens", no_run: @no_dist},
        {"sharding", "Sharding"},
        {"idempotency", "Idempotency and Retries"},
        {"connections", "How Nodes Connect",
         args: ["--name", "connections@127.0.0.1"], no_run: @no_dist}
      ],
      project:
        {"kv", "Spread the store across nodes",
         [
           {"08-replicated-buckets", "Replicated buckets",
            uses: ["nodes", "pg"], args: ["--name", "kv08@127.0.0.1"], no_run: @no_dist},
           {"09-catching-up", "Catching up new nodes",
            uses: ["pg"], args: ["--name", "kv09@127.0.0.1"], no_run: @no_dist},
           {"10-mnesia", "Replicated tables with Mnesia",
            uses: ["nodes"], args: ["--name", "kv10@127.0.0.1"], no_run: @no_dist},
           {"11-libcluster", "Forming the cluster with libcluster",
            uses: ["partitions", "leases"], no_run: @no_dist}
         ]}
    },
    %{
      id: "deployment",
      title: "Deployment",
      blurb:
        "From your laptop to servers: releases, runtime configuration, containers and clusters.",
      examples: [
        {"releases", "Releases"},
        {"runtime-config", "Runtime Configuration"},
        {"containers", "Containers", guide: true},
        {"rolling-deploys", "Rolling Deploys"}
      ],
      project:
        {"kv", "Ship the store",
         [
           {"12-a-release", "KV as a release", uses: ["releases", "runtime-config"]},
           {"13-in-containers", "KV in containers", uses: ["containers"], guide: true},
           {"14-on-kubernetes", "KV on Kubernetes",
            uses: ["containers", "runtime-config"], guide: true}
         ]}
    },
    %{
      id: "production",
      title: "Production",
      blurb:
        "Running it: look inside a live node, find what is slow or leaking, read crash dumps, " <>
          "and change code without a restart.",
      examples: [
        {"hot-code-loading", "Hot Code Loading"},
        {"tracing", "Tracing"},
        {"memory", "Memory: Copies and Binaries"},
        {"mailboxes", "Mailboxes and Slow Consumers"},
        {"load-shedding", "Load Shedding"},
        {"schedulers", "Schedulers and Reductions", args: ["--erl", "+S 1"]},
        {"profiling", "Profiling", no_run: @no_tools},
        {"crash-dumps", "Crash Dumps"},
        {"agent-access", "Letting Agents Debug Production"}
      ],
      project:
        {"kv", "Operate the store",
         [
           {"15-debugging-live", "Debugging KV live",
            uses: ["tracing", "hot-code-loading", "releases"]}
         ]}
    },
    %{
      id: "reliability",
      title: "Reliability",
      blurb:
        "Keeping data right when steps fail: transactions, the outbox pattern and sagas, " <>
          "and a store that protects itself under load.",
      examples: [
        {"transactions", "Transactions and Constraints"},
        {"outbox", "The Outbox Pattern"},
        {"sagas", "Sagas"}
      ],
      project:
        {"kv", "Protect the store",
         [
           {"16-limit-each-client", "Limit each client", uses: ["rate-limiting", "ets"]},
           {"17-bounded-writes", "Bound the writes", uses: ["backpressure", "genserver"]},
           {"18-replicate-behind-a-breaker", "Replicate behind a breaker",
            uses: ["circuit-breaker", "idempotency"]}
         ]}
    }
  ]

  # `base` is the path without extension: either `base.exs` exists (a script)
  # or `base/` is a walkthrough directory.
  source = fn base, slug, title, opts ->
    cond do
      File.regular?(base <> ".exs") ->
        {slug, title, base <> ".exs", Keyword.put(opts, :format, :script)}

      File.regular?(Path.join(base, Ebe.Walkthrough.walkthrough())) ->
        {slug, title, base, Keyword.put(opts, :format, :walkthrough)}

      true ->
        raise CompileError,
          description: "Ebe.Catalog references missing #{Path.relative_to(base, @root)}(.exs)"
    end
  end

  tracks =
    for {t, index} <- Enum.with_index(@tracks, 1) do
      examples =
        for example <- t.examples do
          {slug, title, opts} =
            case example do
              {slug, title} -> {slug, title, []}
              {slug, title, opts} -> {slug, title, opts}
            end

          source.(Path.join([@root, "examples", t.id, slug]), slug, title, opts)
        end

      {project_id, project_title, steps} = t.project

      steps =
        for {slug, title, opts} <- steps do
          source.(Path.join([@root, "projects", project_id, slug]), slug, title, opts)
        end

      # Each project chapter opens with an intro page written in Markdown:
      # projects/<project>/<track>.md
      intro = Path.join([@root, "projects", project_id, t.id <> ".md"])

      all = examples ++ steps

      unless File.regular?(intro) do
        raise CompileError,
          description: "Ebe.Catalog references missing file #{Path.relative_to(intro, @root)}"
      end

      @external_resource intro

      for {_, _, path, opts} <- all do
        case opts[:format] do
          :script ->
            @external_resource path

          :walkthrough ->
            for rel <- [Ebe.Walkthrough.walkthrough() | Ebe.Walkthrough.files(path)] do
              @external_resource Path.join(path, rel)
            end
        end
      end

      dupes =
        all
        |> Enum.frequencies_by(fn {slug, _, _, _} -> slug end)
        |> Enum.filter(fn {_, n} -> n > 1 end)

      if dupes != [] do
        raise CompileError, description: "Duplicate slugs in track #{t.id}: #{inspect(dupes)}"
      end

      Map.merge(t, %{
        index: index,
        examples: examples,
        steps: steps,
        intro: intro,
        project_id: project_id,
        project_title: project_title
      })
    end

  all_example_slugs = for t <- tracks, {slug, _, _, _} <- t.examples, into: MapSet.new(), do: slug

  for t <- tracks, {slug, _, _, opts} <- t.steps, used <- Keyword.get(opts, :uses, []) do
    unless MapSet.member?(all_example_slugs, used) do
      raise CompileError,
        description: "Project step #{slug} uses unknown concept #{inspect(used)}"
    end
  end

  for t <- tracks, {slug, _, _, opts} <- t.examples ++ t.steps, Keyword.has_key?(opts, :no_run) do
    reason = Keyword.fetch!(opts, :no_run)

    unless is_binary(reason) and String.trim(reason) != "" do
      raise CompileError, description: "#{slug}: no_run must be a non-empty string"
    end
  end

  for t <- tracks, {slug, _, _, opts} <- t.examples ++ t.steps, Keyword.get(opts, :guide) do
    unless opts[:format] == :walkthrough do
      raise CompileError, description: "#{slug}: only walkthrough directories can be guides"
    end
  end

  for t <- tracks, {slug, _, _, opts} <- t.examples, Keyword.has_key?(opts, :args) do
    args = Keyword.fetch!(opts, :args)

    unless is_list(args) and Enum.all?(args, &is_binary/1) do
      raise CompileError, description: "#{slug}: args must be a list of strings"
    end
  end

  # Watch the example directories so that adding a file without registering it
  # here is caught by `Ebe.Catalog.unregistered_files/0` in CI.
  @registered_paths for t <- tracks,
                        {_, _, path, _} <- t.examples ++ t.steps,
                        do: Path.relative_to(path, @root)

  @compiled_tracks tracks

  @doc """
  All tracks, in display order, with their examples, project intro and project
  steps as `Entry` structs.
  """
  @spec tracks() :: [Track.t()]
  def tracks do
    Enum.map(@compiled_tracks, fn t ->
      examples = Enum.map(t.examples, &entry(&1, t, :example))
      steps = Enum.map(t.steps, &entry(&1, t, :step))
      intro = entry({t.project_id, t.project_title, t.intro, []}, t, :intro)

      %Track{
        id: t.id,
        index: t.index,
        title: t.title,
        blurb: t.blurb,
        project_id: t.project_id,
        project_title: t.project_title,
        examples: examples,
        intro: intro,
        steps: steps
      }
    end)
  end

  @doc """
  Examples on disk under `examples/` or `projects/` (`.exs` files and
  walkthrough directories) that are not in the catalog.
  """
  @spec unregistered_files() :: [String.t()]
  def unregistered_files do
    walkthrough_dirs =
      Path.wildcard(Path.join(@root, "{examples,projects}/**/" <> Ebe.Walkthrough.walkthrough()))
      |> Enum.map(&(&1 |> Path.dirname() |> Path.relative_to(@root)))

    scripts =
      Path.wildcard(Path.join(@root, "{examples,projects}/**/*.exs"))
      |> Enum.map(&Path.relative_to(&1, @root))
      |> Enum.reject(fn path ->
        Enum.any?(walkthrough_dirs, &String.starts_with?(path, &1 <> "/"))
      end)

    (walkthrough_dirs ++ scripts) -- @registered_paths
  end

  defp entry({slug, title, path, opts}, t, kind) do
    url =
      case kind do
        :example -> "/#{t.id}/#{slug}"
        :step -> "/#{t.id}/#{t.project_id}-#{slug}"
        :intro -> "/#{t.id}/#{t.project_id}"
      end

    %Entry{
      slug: slug,
      title: title,
      kind: kind,
      track_id: t.id,
      source_path: path,
      url: url,
      uses: Keyword.get(opts, :uses, []),
      no_run: Keyword.get(opts, :no_run),
      format: Keyword.get(opts, :format, :script),
      guide: Keyword.get(opts, :guide, false),
      args: Keyword.get(opts, :args, [])
    }
  end
end
