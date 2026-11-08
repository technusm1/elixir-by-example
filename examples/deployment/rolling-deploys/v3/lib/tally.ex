defmodule Tally do
  @moduledoc """
  Version 3 sends the new format. Safe only once every node runs version 2
  or later. It still accepts the old format; a later version can drop it.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, 0, name: __MODULE__)

  @doc "Connects to the node with the given name on this host."
  def join(name), do: Node.connect(:"#{name}@#{host()}")

  @doc "Adds n on every connected node and reports, per node, what happened."
  def add_everywhere(n) do
    for node <- Enum.sort([node() | Node.list()]), do: {short(node), send_add(node, n)}
  end

  defp send_add(node, n) do
    GenServer.call({__MODULE__, node}, {:add, n, node()})
  catch
    :exit, _ -> :crashed
  end

  @impl true
  def init(total), do: {:ok, total}

  @impl true
  def handle_call({:add, n, _from_node}, _from, total), do: {:reply, :ok, total + n}
  def handle_call({:add, n}, _from, total), do: {:reply, :ok, total + n}

  defp host, do: node() |> Atom.to_string() |> String.split("@") |> List.last()
  defp short(node), do: node |> Atom.to_string() |> String.split("@") |> hd() |> String.to_atom()
end

defmodule Tally.Application do
  use Application

  @impl true
  def start(_type, _args), do: Supervisor.start_link([Tally], strategy: :one_for_one)
end
