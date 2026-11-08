defmodule Orders.AgentAccess do
  @moduledoc """
  A narrow, read-only window into the running node for coding agents.

  An SSH daemon (OTP's own `:ssh`) accepts only the keys listed in
  `authorized_keys`, offers no shell, and runs only the commands below. Every
  request, allowed or not, is written to an audit log first.
  """

  @commands %{
    "queues" => "processes with messages waiting, longest queue first (top 3)",
    "where NAME" => "what a registered process is doing (its stack)",
    "help" => "this list"
  }

  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  def start_link do
    config = Application.fetch_env!(:orders, :agent_access)

    :ssh.daemon(config[:port],
      system_dir: String.to_charlist(config[:host_keys]),
      user_dir: String.to_charlist(config[:authorized_keys]),
      auth_methods: ~c"publickey",
      shell: :disabled,
      exec: {:direct, fn command, user -> run(to_string(command), to_string(user)) end}
    )
  end

  defp run(command, user) do
    File.write!(audit_log(), "#{user}: #{command}\n", [:append])

    result =
      case String.split(command) do
        ["queues"] -> {:ok, queues()}
        ["where", name] -> where(name)
        ["help"] -> {:ok, Enum.map_join(@commands, "\n", fn {cmd, what} -> "#{cmd}: #{what}" end)}
        _ -> {:error, "not allowed: #{command} (try: help)"}
      end

    # The SSH client prints the text as is; end it with a newline.
    case result do
      {:ok, text} -> {:ok, text <> "\n"}
      {:error, text} -> {:error, text <> "\n"}
    end
  end

  defp queues do
    Process.list()
    |> Enum.map(&{&1, Process.info(&1, [:registered_name, :message_queue_len])})
    |> Enum.filter(fn {_pid, info} -> info != nil and info[:message_queue_len] > 0 end)
    |> Enum.sort_by(fn {_pid, info} -> -info[:message_queue_len] end)
    |> Enum.take(3)
    |> Enum.map_join("\n", fn {pid, info} -> "#{label(pid, info)}: #{info[:message_queue_len]}" end)
  end

  # Only names that already exist are accepted: String.to_existing_atom/1
  # never creates atoms from untrusted input.
  defp where(name) do
    with {:ok, atom} <- existing_atom(name),
         pid when is_pid(pid) <- Process.whereis(atom),
         {:current_stacktrace, stack} <- Process.info(pid, :current_stacktrace) do
      {:ok, stack |> Enum.take(3) |> Enum.map_join("\n", &Exception.format_stacktrace_entry/1)}
    else
      _ -> {:error, "no process named #{name}"}
    end
  end

  defp existing_atom(name) do
    {:ok, String.to_existing_atom("Elixir." <> name)}
  rescue
    ArgumentError -> :error
  end

  defp label(pid, info) do
    case info[:registered_name] do
      [] -> inspect(pid)
      name -> inspect(name)
    end
  end

  defp audit_log, do: Application.fetch_env!(:orders, :agent_access)[:audit_log]
end
