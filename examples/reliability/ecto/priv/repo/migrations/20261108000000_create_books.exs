defmodule Library.Repo.Migrations.CreateBooks do
  use Ecto.Migration

  # `change` describes the new shape. Ecto works out how to
  # undo it too (`mix ecto.rollback`).
  def change do
    # `create table` adds an `id` primary key by itself.
    create table(:books) do
      add :title, :string, null: false
      add :author, :string, null: false
      add :pages, :integer
      # `inserted_at` and `updated_at`, filled in by Ecto.
      timestamps()
    end

    create unique_index(:books, [:title])
  end
end
