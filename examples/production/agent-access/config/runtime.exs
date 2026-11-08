import Config

# Where the agent-access SSH daemon listens and keeps its keys. Bind it to an
# internal address only; never expose it to the internet.
config :orders, :agent_access,
  port: String.to_integer(System.get_env("AGENT_SSH_PORT", "4022")),
  host_keys: System.fetch_env!("AGENT_SSH_HOST_KEYS"),
  authorized_keys: System.fetch_env!("AGENT_SSH_AUTHORIZED_KEYS"),
  audit_log: System.fetch_env!("AGENT_AUDIT_LOG")
