import Config

config :shop, ecto_repos: [Shop.Repo]
config :shop, Shop.Repo, database: "shop.db", log: false

# Map columns are stored as JSON text. Elixir's built-in
# `JSON` module does the encoding, so no extra dependency.
config :ecto_sqlite3, json_library: JSON
