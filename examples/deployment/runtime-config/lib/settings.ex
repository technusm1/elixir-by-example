defmodule Settings do
  # Read once, when this module is compiled, and frozen into its code.
  @greeting Application.compile_env(:settings, :greeting)

  def greeting, do: @greeting

  def report do
    IO.puts("config.exs said:  " <> Application.fetch_env!(:settings, :built_in))
    IO.puts("runtime.exs said: " <> Application.fetch_env!(:settings, :region))
  end
end
