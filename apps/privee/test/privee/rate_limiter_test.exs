defmodule Privee.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Privee.RateLimiter

  test "limits hits within a window and resets afterwards" do
    key = {:test, make_ref()}
    now = 1_000_000

    assert :ok = RateLimiter.hit(key, 2, 1000, now)
    assert :ok = RateLimiter.hit(key, 2, 1000, now + 1)
    assert :limited = RateLimiter.hit(key, 2, 1000, now + 2)
    assert :ok = RateLimiter.hit(key, 2, 1000, now + 1000)
  end

  test "is shared across processes" do
    key = {:test, make_ref()}
    now = 5_000_000
    Task.await(Task.async(fn -> RateLimiter.hit(key, 1, 1000, now) end))
    assert :limited = RateLimiter.hit(key, 1, 1000, now)
  end
end
