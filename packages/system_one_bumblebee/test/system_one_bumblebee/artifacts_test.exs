defmodule SystemOneBumblebee.ArtifactsTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Artifacts

  test "models without external artifacts prepare offline" do
    assert {:ok, prepared} = Artifacts.prepare(nil)
    assert prepared.pin == nil
    assert prepared.files == %{}
    assert prepared.manifests == %{}
  end
end
