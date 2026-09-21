defmodule SystemOneBumblebeeTest do
  use ExUnit.Case, async: true

  test "package and native dependency modules load together" do
    assert Code.ensure_loaded?(SystemOneBumblebee)
    assert Code.ensure_loaded?(SystemOneContracts)
    assert Code.ensure_loaded?(Nx)
    assert Code.ensure_loaded?(Axon)
    assert Code.ensure_loaded?(Bumblebee)
    assert Code.ensure_loaded?(HfHub)
    assert Code.ensure_loaded?(CrucibleSafetensors)
    assert Application.spec(:system_one_bumblebee, :vsn) == ~c"0.1.0"
  end
end
