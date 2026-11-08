defmodule BillTest do
  use ExUnit.Case
  doctest Bill

  test "shares add up to the total" do
    shares = Bill.split(["10.00"], 3)
    assert Enum.map(shares, &Decimal.to_string/1) == ["3.34", "3.33", "3.33"]
    assert Decimal.equal?(Enum.reduce(shares, &Decimal.add/2), Decimal.new("10.00"))
  end

  test "formats in the test currency" do
    assert Bill.format(Decimal.new("1.50")) == "1.50 XTS"
  end
end
