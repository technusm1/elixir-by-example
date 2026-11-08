defmodule Ebe.Catalog.Entry do
  @moduledoc """
  One page: a concept example or a project step (an `.exs` file that runs, or
  a walkthrough directory, see `Ebe.Walkthrough`), or a project intro (a
  Markdown file).
  """

  @enforce_keys [:slug, :title, :kind, :track_id, :source_path, :url]
  defstruct [
    :slug,
    :title,
    :kind,
    :track_id,
    :source_path,
    :url,
    uses: [],
    no_run: nil,
    args: [],
    format: :script,
    guide: false
  ]

  @type kind :: :example | :step | :intro
  @type format :: :script | :walkthrough

  @type t :: %__MODULE__{
          slug: String.t(),
          title: String.t(),
          kind: kind(),
          track_id: String.t(),
          source_path: Path.t(),
          url: String.t(),
          uses: [String.t()],
          no_run: String.t() | nil,
          args: [String.t()],
          format: format(),
          guide: boolean()
        }
end

defmodule Ebe.Catalog.Track do
  @moduledoc "A group of examples plus the running project built from them."

  alias Ebe.Catalog.Entry

  @enforce_keys [
    :id,
    :index,
    :title,
    :blurb,
    :project_id,
    :project_title,
    :examples,
    :intro,
    :steps
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          index: pos_integer(),
          title: String.t(),
          blurb: String.t(),
          project_id: String.t(),
          project_title: String.t(),
          examples: [Entry.t()],
          intro: Entry.t(),
          steps: [Entry.t()]
        }
end
