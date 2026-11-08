import Config

# Tells the `mix ecto.*` tasks which repos this app has.
config :library, ecto_repos: [Library.Repo]

# The repo's settings. `log: false` keeps query logs (with
# their timings) out of the output. SQLite allows one
# writer at a time, so one connection is enough.
config :library, Library.Repo, database: "library.db", log: false, pool_size: 1
