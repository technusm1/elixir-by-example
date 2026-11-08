defmodule Bill do
  @moduledoc "Adds up a bill and splits it, in exact decimal arithmetic."

  @doc """
  Adds up prices given as strings.

      iex> Bill.total(["0.10", "0.20"])
      Decimal.new("0.30")
  """
  @spec total([String.t()]) :: Decimal.t()
  def total(prices) do
    Enum.reduce(prices, Decimal.new(0), &Decimal.add(Decimal.new(&1), &2))
  end

  @doc """
  Splits the total between `people`, to the cent. Shares differ by at most
  one cent and always add up to the total.
  """
  @spec split([String.t()], pos_integer()) :: [Decimal.t()]
  def split(prices, people) when is_integer(people) and people > 0 do
    cents = prices |> total() |> Decimal.mult(100) |> Decimal.to_integer()
    share = div(cents, people)
    extra = rem(cents, people)

    for n <- 1..people do
      Decimal.new(1, if(n <= extra, do: share + 1, else: share), -2)
    end
  end

  @doc "Formats an amount in the configured currency."
  @spec format(Decimal.t()) :: String.t()
  def format(amount) do
    Decimal.to_string(amount) <> " " <> Application.fetch_env!(:bill, :currency)
  end
end
