defmodule SystemOneBumblebee.ModelRegistryTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.{Adapters.Fake, ModelRegistry}

  test "resolves explicit models and aliases" do
    assert {:ok, registry} =
             ModelRegistry.new(%{
               "native-fixture" => %{
                 adapter: Fake,
                 aliases: ["fixture", "fixture-v1"]
               }
             })

    assert {:ok, manifest} = ModelRegistry.resolve(registry, "native-fixture")
    assert manifest.name == "native-fixture"
    assert {:ok, ^manifest} = ModelRegistry.resolve(registry, "fixture")
    assert {:error, :model_not_found} = ModelRegistry.resolve(registry, "missing")
  end

  test "rejects a canonical model name that collides with an earlier alias" do
    assert {:error, {:model_conflicts_with_alias, "b"}} =
             ModelRegistry.new([
               %SystemOneBumblebee.ModelManifest{
                 name: "a",
                 adapter: Fake,
                 aliases: ["b"],
                 capabilities: SystemOneContracts.Capabilities.core(),
                 metadata: %{},
                 pin: nil,
                 adapter_options: []
               },
               %SystemOneBumblebee.ModelManifest{
                 name: "b",
                 adapter: Fake,
                 aliases: [],
                 capabilities: SystemOneContracts.Capabilities.core(),
                 metadata: %{},
                 pin: nil,
                 adapter_options: []
               }
             ])
  end

  test "rejects alias collisions" do
    assert {:error, {:duplicate_alias, "shared"}} =
             ModelRegistry.new(%{
               "a" => %{adapter: Fake, aliases: ["shared"]},
               "b" => %{adapter: Fake, aliases: ["shared"]}
             })
  end
end
