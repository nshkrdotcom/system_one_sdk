defmodule SystemOneBumblebee.Models.Laya.ModelTest do
  use ExUnit.Case,
    async: true

  alias SystemOneBumblebee.Adapters.Laya

  alias SystemOneBumblebee.Models.Laya.Model

  test "committed Laya identity has an immutable five-file artifact pin" do
    assert {:ok, pin} =
             Model.artifact_pin()

    assert pin.repo_id ==
             "convaiinnovations/laya"

    assert byte_size(pin.revision) == 40

    assert length(pin.files) == 5

    assert Enum.map(
             pin.files,
             & &1.path
           ) ==
             [
               "model.safetensors",
               "rl_agent_config.json",
               "encoder/config.json",
               "tokenizer/tokenizer.json",
               "tokenizer/tokenizer_config.json"
             ]

    assert Enum.all?(
             pin.files,
             &(byte_size(&1.sha256) == 64)
           )
  end

  test "model manifest selects the production Laya adapter" do
    assert {:ok, manifest} =
             Model.manifest()

    assert manifest.name ==
             "laya-rl-agent"

    assert manifest.adapter ==
             Laya

    assert "laya" in manifest.aliases

    assert "question:choice" in manifest.capabilities

    assert manifest.pin.revision ==
             "c5d78730f3493e4fe16d61507ef4b78eef7318cf"
  end
end
