defmodule SystemOneBumblebeeTest do
  use ExUnit.Case, async: true

  test "package and SDK modules load together" do
    assert Code.ensure_loaded?(SystemOneBumblebee)
    assert Code.ensure_loaded?(SystemOneSDK)
    assert Application.spec(:system_one_bumblebee, :vsn) == ~c"0.1.0"
  end
end
