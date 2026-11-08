defmodule Span do
  @moduledoc "Parses and formats durations such as `1h30m`."

  @units %{"d" => 86_400, "h" => 3_600, "m" => 60, "s" => 1}

  @doc """
  Parses a duration into seconds.

      iex> Span.parse("1h30m")
      {:ok, 5400}

      iex> Span.parse("90x")
      {:error, {:unknown_unit, "x"}}
  """
  @spec parse(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def parse(""), do: {:error, :empty}

  def parse(text) do
    with {:ok, seconds} <- parse(text, 0) do
      max = Application.get_env(:span, :max_seconds, 7 * 86_400)
      if seconds <= max, do: {:ok, seconds}, else: {:error, {:too_long, seconds}}
    end
  end

  defp parse("", total), do: {:ok, total}

  defp parse(text, total) do
    case Integer.parse(text) do
      {n, rest} when n >= 0 ->
        {unit, rest} = String.split_at(rest, 1)

        case Map.fetch(@units, unit) do
          {:ok, size} -> parse(rest, total + n * size)
          :error when unit == "" -> {:error, {:missing_unit, n}}
          :error -> {:error, {:unknown_unit, unit}}
        end

      _ ->
        {:error, {:not_a_number, text}}
    end
  end

  @doc "Like `parse/1`, but raises `ArgumentError` on bad input."
  @spec parse!(String.t()) :: non_neg_integer()
  def parse!(text) do
    case parse(text) do
      {:ok, seconds} -> seconds
      {:error, reason} -> raise ArgumentError, "bad duration #{inspect(text)}: #{inspect(reason)}"
    end
  end

  @doc """
  Formats seconds, biggest unit first, skipping zero parts.

      iex> Span.format(5400)
      "1h 30m"
  """
  @spec format(non_neg_integer()) :: String.t()
  def format(0), do: "0s"

  def format(seconds) do
    {parts, 0} =
      Enum.reduce(~w(d h m s), {[], seconds}, fn unit, {parts, left} ->
        size = @units[unit]
        count = div(left, size)
        parts = if count > 0, do: ["#{count}#{unit}" | parts], else: parts
        {parts, rem(left, size)}
      end)

    parts |> Enum.reverse() |> Enum.join(" ")
  end
end
