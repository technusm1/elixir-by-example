import Config

config :shop, ecto_repos: [Shop.Repo]
# SQLite allows one writer at a time, so one connection
# is enough, and it stops several connections racing to
# open a fresh database file.
config :shop, Shop.Repo, database: "shop.db", log: false, pool_size: 1

# Map columns are stored as JSON text. Elixir's built-in
# `JSON` module does the encoding, so no extra dependency.
config :ecto_sqlite3, json_library: JSON
