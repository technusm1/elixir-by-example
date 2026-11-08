defmodule Library do
  import Ecto.Query
  alias Library.{Book, Repo}

  def add_book(attrs) do
    %Book{}
    |> Book.changeset(attrs)
    |> Repo.insert()
  end

  def set_pages(title, pages) do
    Repo.get_by!(Book, title: title)
    |> Book.changeset(%{pages: pages})
    |> Repo.update()
  end

  def remove(title), do: Repo.delete(Repo.get_by!(Book, title: title))

  # Keyword syntax: the whole query in one `from`.
  # `^author` puts an Elixir value into the query (as a
  # parameter, never pasted into the SQL text).
  def titles_by(author) do
    query =
      from b in Book,
        where: b.author == ^author,
        order_by: b.title,
        select: b.title

    Repo.all(query)
  end

  # Pipe syntax: the same building blocks as functions.
  # Each step takes a query and returns a bigger one.
  def shorter_than(pages) do
    Book
    |> where([b], b.pages < ^pages)
    |> order_by([b], asc: b.pages)
    |> select([b], {b.title, b.pages})
    |> Repo.all()
  end

  # Turns a changeset's errors into a map of readable
  # messages, filling in `%{count}` and friends.
  def errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
