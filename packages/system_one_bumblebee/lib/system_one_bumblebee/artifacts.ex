defmodule SystemOneBumblebee.Artifacts.Prepared do
  @moduledoc "Verified local artifact paths supplied to a model adapter."

  alias SystemOneBumblebee.ArtifactPin

  @enforce_keys [:pin, :files, :manifests]
  defstruct [:pin, :files, :manifests]

  @type t :: %__MODULE__{
          pin: ArtifactPin.t() | nil,
          files: %{String.t() => Path.t()},
          manifests: %{String.t() => map()}
        }
end

defmodule SystemOneBumblebee.Artifacts do
  @moduledoc """
  Fetches and verifies immutable model files before an adapter allocates tensors.

  `hf_hub` owns download/cache mechanics. `crucible_safetensors` independently
  verifies file hashes and, when supplied, validates SafeTensors header manifests.
  """

  alias SystemOneBumblebee.ArtifactPin
  alias SystemOneBumblebee.Artifacts.Prepared

  @spec prepare(ArtifactPin.t() | nil, keyword()) :: {:ok, Prepared.t()} | {:error, term()}
  def prepare(pin, opts \\ [])

  def prepare(nil, _opts), do: {:ok, %Prepared{pin: nil, files: %{}, manifests: %{}}}

  def prepare(%ArtifactPin{} = pin, opts) when is_list(opts) do
    token = Keyword.get(opts, :token)
    force_download = Keyword.get(opts, :force_download, false)

    pin.files
    |> Enum.reduce_while({:ok, %{}, %{}}, fn file, {:ok, paths, manifests} ->
      case prepare_file(pin, file, token, force_download) do
        {:ok, path, manifest_report} ->
          {:cont,
           {:ok, Map.put(paths, file.path, path),
            maybe_put(manifests, file.path, manifest_report)}}

        {:error, reason} ->
          {:halt, {:error, {:artifact_prepare_failed, file.path, reason}}}
      end
    end)
    |> case do
      {:ok, paths, manifests} ->
        {:ok, %Prepared{pin: pin, files: paths, manifests: manifests}}

      error ->
        error
    end
  end

  def prepare(other, _opts), do: {:error, {:invalid_artifact_pin, other}}

  defp prepare_file(pin, file, token, force_download) do
    download_opts = [
      repo_id: pin.repo_id,
      repo_type: pin.repo_type,
      revision: pin.revision,
      filename: file.path,
      expected_sha256: file.sha256,
      force_download: force_download
    ]

    download_opts = if token, do: Keyword.put(download_opts, :token, token), else: download_opts

    with {:ok, path} <- HfHub.Download.hf_hub_download(download_opts),
         {:ok, _digest} <- CrucibleSafetensors.Checksum.verify_file(path, file.sha256),
         {:ok, report} <- validate_manifest(path, file) do
      {:ok, path, report}
    end
  end

  defp validate_manifest(_path, %{tensors: nil}), do: {:ok, nil}

  defp validate_manifest(path, %{tensors: tensors, exact_tensors: exact?}) do
    with {:ok, report} <- CrucibleSafetensors.Manifest.validate_file(path, tensors, exact: exact?),
         true <- report.valid? do
      {:ok, report}
    else
      false -> {:error, :tensor_manifest_mismatch}
      {:error, _} = error -> error
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
