import Config

config :bank, ecto_repos: [Bank.Repo]

# `log: false` keeps query logs (with their timings) out
# of the output. SQLite allows one writer at a time, so
# one connection is enough, and it stops several
# connections racing to open a fresh database file.
config :bank, Bank.Repo, database: "bank.db", log: false, pool_size: 1
