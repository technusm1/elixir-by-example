defmodule Shop.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :item, :string, null: false
    end

    # Events waiting to be published. `published_at`
    # stays empty until the relay has sent the event.
    create table(:outbox) do
      add :topic, :string, null: false
      add :payload, :map, null: false
      add :published_at, :utc_datetime
    end
  end
end
