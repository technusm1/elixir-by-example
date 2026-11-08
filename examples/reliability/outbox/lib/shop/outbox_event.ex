defmodule Shop.OutboxEvent do
  use Ecto.Schema

  schema "outbox" do
    field :topic, :string
    field :payload, :map
    field :published_at, :utc_datetime
  end
end
