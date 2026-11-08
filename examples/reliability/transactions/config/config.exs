import Config

config :bank, ecto_repos: [Bank.Repo]

# `log: false` keeps query logs (with their timings) out
# of the output.
config :bank, Bank.Repo, database: "bank.db", log: false
