defmodule Ebe.Page do
  @moduledoc "Everything needed to render one example or project step."

  alias Ebe.Catalog.Entry

  defmodule Segment do
    @moduledoc """
    A rendered prose/code pair. `cell` numbers code cells from 1 (nil for
    prose-only segments), `line` is the cell's first line in the program
    (code cells joined without prose, numbered from 1),
    and `output` is what that cell printed.
    """
    @enforce_keys [:doc_html, :code_html, :code, :cell, :line, :output]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            doc_html: String.t(),
            code_html: String.t(),
            code: String.t(),
            cell: pos_integer() | nil,
            line: pos_integer() | nil,
            output: String.t() | nil
          }
  end

  @enforce_keys [
    :entry,
    :source,
    :program,
    :segments,
    :output,
    :description,
    :uses,
    :edit_url
  ]
  defstruct [
    :entry,
    :source,
    :program,
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
          program: String.t(),
          segments: [Segment.t()],
          output: String.t(),
          description: String.t(),
          uses: [Entry.t()],
          edit_url: String.t(),
          prev: Entry.t() | nil,
          next: Entry.t() | nil
        }
end
