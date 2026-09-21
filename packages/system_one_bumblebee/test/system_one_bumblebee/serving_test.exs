defmodule SystemOneBumblebee.ServingTest do
  use ExUnit.Case, async: false

  alias SystemOneBumblebee.{Adapters.Fake, ModelManifest, RuntimeProfile, ServingSupervisor}

  test "a canonical model gets one resident serving process" do
    name = "serving-#{System.unique_integer([:positive])}"
    assert {:ok, manifest} = ModelManifest.new(name, adapter: Fake)
    profile = RuntimeProfile.test()

    assert {:ok, first} = ServingSupervisor.ensure_started(manifest, profile)
    assert {:ok, second} = ServingSupervisor.ensure_started(manifest, profile)
    assert first == second
    assert Process.alive?(first)

    assert :ok = ServingSupervisor.stop_model(name)
  end
end
