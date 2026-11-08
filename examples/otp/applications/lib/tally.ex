defmodule Tally do
  @moduledoc "Counts hits per page name."

  # Read once, when this module is compiled: a guard needs a constant.
  @max_name_length Application.compile_env(:tally, :max_name_length)

  def hit(name) when is_binary(name) and byte_size(name) <= @max_name_length do
    with {:ok, pid} <- counter(name) do
      Tally.Total.add()
      {:ok, Tally.Counter.hit(pid)}
    end
  end

  def hit(name) when is_binary(name), do: {:error, :name_too_long}

  defp counter(name) do
    case Registry.lookup(Tally.Names, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_counter(name)
    end
  end

  defp start_counter(name) do
    case DynamicSupervisor.start_child(Tally.Counters, {Tally.Counter, name}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, :max_children} -> {:error, :too_many_counters}
    end
  end
end
