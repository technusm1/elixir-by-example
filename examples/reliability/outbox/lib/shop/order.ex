defmodule Shop.Order do
  use Ecto.Schema

  schema "orders" do
    field :item, :string
  end
end
