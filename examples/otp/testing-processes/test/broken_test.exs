defmodule BrokenTest do
  # Wrong on purpose, to show what a missing message looks like. Excluded by
  # default.
  use ExUnit.Case, async: true
  @moduletag :broken

  test "waits for a message that never comes" do
    meter = start_supervised!({Quota.Meter, limit: 1, interval: :timer.hours(1), notify: self()})
    Quota.Meter.hit(meter, "a")
    Quota.Meter.hit(meter, "a")
    assert_receive {:over_limit, "b"}
  end
end
