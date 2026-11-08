import Config

config :bill, currency: "EUR"

# Last, so the environment's file can override anything above.
import_config "#{config_env()}.exs"
