defmodule SystemOneBumblebee.Models.Laya.RuntimeContractTest do
  use ExUnit.Case,
    async: true

  alias SystemOneBumblebee.{
    Artifacts,
    RuntimeProfile
  }

  alias SystemOneBumblebee.Models.Laya.{
    Model,
    Runtime
  }

  test "runtime refuses an unspecified model parameter type" do
    assert {:ok, manifest} =
             Model.manifest()

    prepared =
      %Artifacts.Prepared{
        pin: manifest.pin,
        files: %{},
        manifests: %{}
      }

    profile =
      RuntimeProfile.new!(name: :missing_type)

    assert {:error, {:invalid_laya_runtime_type, nil}} =
             Runtime.load(
               manifest,
               prepared,
               profile
             )
  end

  test "runtime requires every verified artifact before allocation" do
    assert {:ok, manifest} =
             Model.manifest()

    prepared =
      %Artifacts.Prepared{
        pin: manifest.pin,
        files: %{},
        manifests: %{}
      }

    assert {:error, {:missing_laya_artifacts, missing}} =
             Runtime.load(
               manifest,
               prepared,
               RuntimeProfile.cpu()
             )

    assert Enum.sort(missing) ==
             Enum.sort([
               "model.safetensors",
               "rl_agent_config.json",
               "encoder/config.json",
               "tokenizer/tokenizer.json"
             ])
  end
end
