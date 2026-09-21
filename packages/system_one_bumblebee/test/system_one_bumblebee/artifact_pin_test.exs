defmodule SystemOneBumblebee.ArtifactPinTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.ArtifactPin

  @revision String.duplicate("a", 40)
  @sha256 String.duplicate("b", 64)

  test "accepts immutable revision and SHA-pinned files" do
    assert {:ok, pin} =
             ArtifactPin.new(
               repo_id: "owner/model",
               revision: @revision,
               files: [%{path: "model.safetensors", sha256: @sha256}]
             )

    assert pin.revision == @revision
    assert [%{path: "model.safetensors", sha256: @sha256}] = pin.files
  end

  test "rejects mutable revisions" do
    assert {:error, {:mutable_or_invalid_revision, "main"}} =
             ArtifactPin.new(
               repo_id: "owner/model",
               revision: "main",
               files: [%{path: "model.safetensors", sha256: @sha256}]
             )
  end

  test "rejects traversal and invalid hashes" do
    assert {:error, {:invalid_artifact_path, "../model.safetensors"}} =
             ArtifactPin.new(
               repo_id: "owner/model",
               revision: @revision,
               files: [%{path: "../model.safetensors", sha256: @sha256}]
             )

    assert {:error, {:invalid_sha256, "bad"}} =
             ArtifactPin.new(
               repo_id: "owner/model",
               revision: @revision,
               files: [%{path: "model.safetensors", sha256: "bad"}]
             )
  end
end
