defmodule Mix.Tasks.Ebe.Server do
  @shortdoc "Builds the site, serves dist/ and rebuilds on changes"
  @moduledoc """
  Local preview at http://localhost:4000 with the same cross-origin isolation
  headers as production (needed by Popcorn). Rebuilds when files under
  `examples/`, `projects/` or `priv/static/` change. Restart it after editing
  code under `lib/`.

      mix ebe.server [--port 4000]
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [port: :integer])
    port = Keyword.get(opts, :port, 4000)

    Application.ensure_all_started([:mdex, :bandit, :file_system])
    rebuild()

    {:ok, _} = Bandit.start_link(plug: Ebe.DevServer, port: port, startup_log: false)
    Mix.shell().info("Serving http://localhost:#{port}")

    {:ok, watcher} = FileSystem.start_link(dirs: ["examples", "projects", "priv/static"])
    FileSystem.subscribe(watcher)
    loop()
  end

  defp loop do
    receive do
      {:file_event, _pid, {path, _events}} ->
        if Path.extname(path) in [".exs", ".css", ".js", ".png"] do
          drain()
          rebuild()
        end

        loop()
    end
  end

  # Coalesce bursts of events (editors write several times per save).
  defp drain do
    receive do
      {:file_event, _, _} -> drain()
    after
      100 -> :ok
    end
  end

  defp rebuild do
    Ebe.Build.run()
  rescue
    e -> Mix.shell().error(Exception.message(e))
  end
end
