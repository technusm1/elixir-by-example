defmodule Mix.Tasks.Ebe.Build do
  @shortdoc "Runs every example and builds the static site into dist/"
  @moduledoc """
  Runs every example on the BEAM and renders the site.

      mix ebe.build            # build into dist/
      mix ebe.build --out tmp  # build somewhere else

  Fails if any example exits non-zero, times out, or emits a warning.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [out: :string])
    Application.ensure_all_started(:mdex)
    Ebe.Build.run(opts)
  end
end
