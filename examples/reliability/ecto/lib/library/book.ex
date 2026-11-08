defmodule Library.Book do
  use Ecto.Schema
  import Ecto.Changeset

  # Maps the `books` table to a `%Library.Book{}` struct.
  # `id` is added by default, as in the migration.
  schema "books" do
    field :title, :string
    field :author, :string
    field :pages, :integer
    timestamps()
  end

  # Every write goes through here: pick the fields an
  # outsider may set, convert them to the field types,
  # then validate.
  def changeset(book, attrs) do
    book
    |> cast(attrs, [:title, :author, :pages])
    |> validate_required([:title, :author])
    |> validate_length(:title, min: 2)
    |> validate_number(:pages, greater_than: 0)
    |> unique_constraint(:title)
  end
end
