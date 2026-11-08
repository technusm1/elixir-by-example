Placing an order means two things: save the order in your database, and tell
other systems about it (billing, shipping, email) through a message broker. The
obvious code does one and then the other. That's a *dual write*, and it has a
gap: if the node stops between the two (a deploy, an out-of-memory kill, a lost
machine), the order exists and nobody is ever told. Doing them the other way
round has the opposite gap: an announced order that doesn't exist.

There's no transaction that spans your database and a broker. The *outbox
pattern* avoids needing one. The event is written to an `outbox` table in the
*same* transaction as the order, so both exist or neither does. A separate
*relay* process reads the table, publishes what it finds, and marks it as
sent. If the node dies, the event waits in the table until the relay runs again.

On this page:

1. A dual write loses an event when the node stops at the wrong moment.
2. The outbox keeps it, and the relay publishes it after the restart.
3. The price: the relay can publish an event twice, so consumers must be ready
   for duplicates.

## The project

The same setup as [Transactions and Constraints](/reliability/transactions):
Ecto on SQLite.

```file mix.exs
```

```file config/config.exs
```

```file lib/shop/repo.ex
```

The application starts the repo and the relay.

```file lib/shop/application.ex
```

```file priv/repo/migrations/20261108000000_create_orders.exs
```

```file lib/shop/order.ex
```

```file lib/shop/outbox_event.ex
```

The "broker" is a file standing in for Kafka or RabbitMQ. What matters is that
it lives outside the shop's node: what it was sent survives the node going
down, and so does the database. Everything in the node's memory doesn't.

```file lib/shop/broker.ex
```

Both ways of placing an order. `crash_after_commit: true` halts the node right
after the transaction commits, the worst moment for a dual write.

```file lib/shop.ex
```

The relay polls the outbox once a second. `flush/1` runs a pass on demand so
the output below doesn't depend on timing, and `crash_before_mark: true` halts
the node after publishing an event but before marking it as sent.

```file lib/shop/relay.ex
```

## Set up

```sh
mix deps.get > /dev/null
mix deps.compile > /dev/null 2>&1
mix compile
mix ecto.create --quiet
mix ecto.migrate --quiet
```

## A dual write loses the event

The node stops between the commit and the publish. `mix run` exits with
status 1, as the node would have.

```sh fails
mix run -e 'Shop.place_order_dual_write("book", crash_after_commit: true)'
```

After a restart the order is there. The broker never heard of it, and nothing
remembers that it should have.

```sh
mix run -e 'IO.inspect(Shop.orders(), label: "orders"); IO.inspect(Shop.Broker.received(), label: "broker")'
```

## The outbox keeps it

The same crash, with the outbox.

```sh fails
mix run -e 'Shop.place_order("lamp", crash_after_commit: true)'
```

After the restart the event is still in the outbox, and the relay's first pass
publishes it.

```sh
mix run -e '
IO.inspect(Shop.orders(), label: "orders")
IO.inspect(Shop.Relay.flush(), label: "events published")
Enum.each(Shop.Broker.received(), &IO.puts/1)
'
```

## At least once, not exactly once

The relay publishes and *then* marks the row. If the node stops between the
two, the row still looks unsent.

```sh fails
mix run -e 'Shop.place_order("pen"); Shop.Relay.flush(crash_before_mark: true)'
```

So after the restart the relay publishes it again, and the broker has the
`pen` event twice.

```sh
mix run -e '
IO.inspect(Shop.Relay.flush(), label: "events published")
Enum.each(Shop.Broker.received(), &IO.puts/1)
'
```

Marking first and publishing second would turn the duplicate into a loss,
which is worse. No ordering of the two steps gives *exactly once*. The outbox
gives *at least once*, and the consumers make repeats harmless: every event
carries a unique id (`outbox-2` here), and a consumer that has already handled
an id skips it. See [Idempotency and Retries](/distributed/idempotency).

> **Pitfall:** don't publish from inside the transaction "to be safe". If the
> transaction then rolls back, the event announces an order that never
> existed, and you can't take it back.

> **Pitfall:** with more than one relay (one per node), two relays can pick
> up the same row and publish it twice, more often than any crash would. Run
> one relay per cluster (a singleton, or a lease as on
> [Leases and Fencing Tokens](/distributed/leases)), or have each relay claim
> rows (Postgres: `SELECT ... FOR UPDATE SKIP LOCKED`).

> **Pitfall:** the outbox table only grows. Delete published rows after a
> while, or the relay's query gets slower every day.
