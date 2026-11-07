defmodule Ebe.Page do
  @moduledoc "Everything needed to render one example or project step."

  alias Ebe.Catalog.Entry

  defmodule Segment do
    @moduledoc "A rendered prose/code pair."
    @enforce_keys [:doc_html, :code_html]
    defstruct [:doc_html, :code_html]
    @type t :: %__MODULE__{doc_html: String.t(), code_html: String.t()}
  end

  @enforce_keys [:entry, :source, :segments, :output, :description, :uses, :edit_url]
  defstruct [
    :entry,
    :source,
    :segments,
    :output,
    :description,
    :uses,
    :edit_url,
    prev: nil,
    next: nil
  ]

  @type t :: %__MODULE__{
          entry: Entry.t(),
          source: String.t(),
          segments: [Segment.t()],
          output: String.t(),
          description: String.t(),
          uses: [Entry.t()],
          edit_url: String.t(),
          prev: Entry.t() | nil,
          next: Entry.t() | nil
        }
end
