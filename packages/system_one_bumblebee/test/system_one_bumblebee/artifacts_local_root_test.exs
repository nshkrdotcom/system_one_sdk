defmodule SystemOneBumblebee.ArtifactsLocalRootTest do
  use ExUnit.Case,
    async: true

  alias SystemOneBumblebee.{
    ArtifactPin,
    Artifacts
  }

  test "local artifact roots use the same committed SHA-256 verification" do
    root =
      Path.join(
        System.tmp_dir!(),
        "system-one-artifacts-" <>
          Integer.to_string(System.unique_integer([:positive]))
      )

    path =
      Path.join(
        root,
        "nested/fixture.bin"
      )

    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      "verified local artifact"
    )

    on_exit(fn ->
      File.rm_rf(root)
    end)

    sha256 =
      path
      |> File.read!()
      |> then(
        &:crypto.hash(
          :sha256,
          &1
        )
      )
      |> Base.encode16(case: :lower)

    pin =
      ArtifactPin.new!(
        repo_id: "fixture/model",
        revision:
          String.duplicate(
            "a",
            40
          ),
        files: [
          %{
            path: "nested/fixture.bin",
            sha256: sha256
          }
        ]
      )

    assert {:ok, prepared} =
             Artifacts.prepare(
               pin,
               local_root: root
             )

    assert prepared.files ==
             %{
               "nested/fixture.bin" => path
             }
  end
end
