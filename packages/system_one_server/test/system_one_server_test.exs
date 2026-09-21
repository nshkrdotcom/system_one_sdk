defmodule SystemOneServerTest do
  use ExUnit.Case, async: true

  test "package and contracts modules load together" do
    assert Code.ensure_loaded?(SystemOneServer)
    assert Code.ensure_loaded?(SystemOneContracts)
    assert Application.spec(:system_one_server, :vsn) == ~c"0.1.0"
  end
end
