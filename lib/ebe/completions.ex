defmodule Ebe.Completions do
  @moduledoc """
  Builds `completions.json`, the data behind autocomplete in the browser editor.

  The function lists come from the BEAM the site is built with (`__info__/1`
  for Elixir modules, `module_info/1` for Erlang ones), so they always match
  the Elixir/OTP version the examples are verified on. The browser loads the
  file the first time a reader focuses a code cell.
  """

  @elixir_modules [
    Access,
    Agent,
    Application,
    Base,
    Code,
    Date,
    DateTime,
    DynamicSupervisor,
    Enum,
    Exception,
    File,
    Float,
    Function,
    GenServer,
    Integer,
    IO,
    Kernel,
    Keyword,
    List,
    Map,
    MapSet,
    NaiveDateTime,
    Node,
    Path,
    Process,
    Range,
    Regex,
    Registry,
    Stream,
    String,
    Supervisor,
    System,
    Task,
    Task.Supervisor,
    Time,
    Tuple,
    URI
  ]

  @erlang_modules [
    :atomics,
    :counters,
    :erlang,
    :ets,
    :global,
    :lists,
    :maps,
    :persistent_term,
    :pg,
    :queue,
    :rand,
    :timer
  ]

  # Words that are valid on their own (no module prefix).
  @special_forms ~w(case cond fn for if receive try unless with quote unquote
    def defp defmodule defstruct defprotocol defimpl defmacro defguard
    defexception defdelegate import alias require use do end after rescue
    catch else when true false nil __MODULE__)

  @doc "The completions as a JSON string."
  @spec json() :: String.t()
  def json do
    modules =
      Map.new(@elixir_modules ++ @erlang_modules, fn mod -> {name(mod), functions(mod)} end)

    kernel = Map.fetch!(modules, "Kernel") |> Enum.map(&hd(String.split(&1, "/")))
    words = Enum.uniq(@special_forms ++ kernel) |> Enum.sort()

    JSON.encode!(%{"modules" => modules, "words" => words})
  end

  defp name(mod) when is_atom(mod) do
    case Atom.to_string(mod) do
      "Elixir." <> rest -> rest
      erlang -> ":" <> erlang
    end
  end

  defp functions(mod) do
    {:module, ^mod} = Code.ensure_loaded(mod)

    exports =
      if function_exported?(mod, :__info__, 1),
        do: mod.__info__(:functions) ++ mod.__info__(:macros),
        else: mod.module_info(:exports) -- [module_info: 0, module_info: 1]

    exports
    |> Enum.reject(fn {fun, _} -> String.starts_with?(Atom.to_string(fun), "_") end)
    |> Enum.map(fn {fun, arity} -> "#{fun}/#{arity}" end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
