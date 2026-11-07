defmodule Ebe.Catalog.Entry do
  @moduledoc "One page: a concept example or a project step."

  @enforce_keys [:slug, :title, :kind, :track_id, :source_path, :url]
  defstruct [:slug, :title, :kind, :track_id, :source_path, :url, uses: [], no_run: nil]

  @type kind :: :example | :step

  @type t :: %__MODULE__{
          slug: String.t(),
          title: String.t(),
          kind: kind(),
          track_id: String.t(),
          source_path: Path.t(),
          url: String.t(),
          uses: [String.t()],
          no_run: String.t() | nil
        }
end

defmodule Ebe.Catalog.Track do
  @moduledoc "A group of examples plus the running project built from them."

  alias Ebe.Catalog.Entry

  @enforce_keys [:id, :index, :title, :blurb, :project_id, :project_title, :examples, :steps]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          index: pos_integer(),
          title: String.t(),
          blurb: String.t(),
          project_id: String.t(),
          project_title: String.t(),
          examples: [Entry.t()],
          steps: [Entry.t()]
        }
end
