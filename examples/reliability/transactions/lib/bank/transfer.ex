defmodule Bank.Transfer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transfers" do
    field :key, :string
    field :from_id, :integer
    field :to_id, :integer
    field :amount, :integer
  end

  def record(key, from, to, amount) do
    %Bank.Transfer{}
    |> change(key: key, from_id: from.id, to_id: to.id, amount: amount)
    |> unique_constraint(:key)
  end
end
