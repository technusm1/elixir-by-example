import Config

# Evaluated when the release is BUILT, on the build machine.
config :settings, built_in: System.get_env("REGION", "unset")
config :settings, greeting: "hello"
