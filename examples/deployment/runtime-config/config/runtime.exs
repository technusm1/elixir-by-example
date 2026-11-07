import Config

# Evaluated every time the release STARTS, on the machine it starts on.
config :settings, region: System.get_env("REGION", "unset")
config :settings, api_key: System.fetch_env!("API_KEY")

if greeting = System.get_env("GREETING") do
  config :settings, greeting: greeting
end
