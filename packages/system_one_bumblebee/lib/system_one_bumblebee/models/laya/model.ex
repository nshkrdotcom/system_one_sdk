defmodule SystemOneBumblebee.Models.Laya.Model do
  @moduledoc """
  Committed model identity for the English Laya runtime.
  """

  alias SystemOneBumblebee.{
    ArtifactPin,
    ModelManifest
  }

  alias SystemOneBumblebee.Adapters.Laya,
    as: LayaAdapter

  @name "laya-rl-agent"
  @artifact_manifest "priv/models/laya/artifacts.json"

  @spec name() :: String.t()
  def name,
    do: @name

  @spec artifact_pin() ::
          {:ok, ArtifactPin.t()}
          | {:error, term()}
  def artifact_pin do
    with {:ok, bytes} <-
           File.read(artifact_manifest_path()),
         {:ok, json} <-
           Jason.decode(bytes),
         {:ok, pin} <-
           ArtifactPin.new(json) do
      {:ok, pin}
    else
      {:error, reason} ->
        {:error, {:laya_artifact_manifest_invalid, reason}}
    end
  end

  @spec manifest(keyword()) ::
          {:ok, ModelManifest.t()}
          | {:error, term()}
  def manifest(opts \\ [])
      when is_list(opts) do
    with {:ok, pin} <-
           artifact_pin() do
      ModelManifest.new(
        Keyword.get(
          opts,
          :name,
          @name
        ),
        adapter: LayaAdapter,
        pin: pin,
        aliases:
          Keyword.get(
            opts,
            :aliases,
            ["laya"]
          ),
        capabilities: LayaAdapter.capabilities(nil),
        description: "Native Laya 0.3.3 System One model",
        metadata: %{
          "family" => "laya",
          "provider" => "convaiinnovations/laya",
          "artifact_revision" => pin.revision
        },
        adapter_options:
          Keyword.get(
            opts,
            :adapter_options,
            []
          )
      )
    end
  end

  defp artifact_manifest_path do
    Application.app_dir(
      :system_one_bumblebee,
      @artifact_manifest
    )
  end
end
