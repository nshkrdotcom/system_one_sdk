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

  Applications that already stage an immutable revision may pass `:local_root`.
  The same committed SHA-256 and tensor-manifest checks are applied to files
  under that directory; local staging never bypasses artifact verification.
  """

  alias SystemOneBumblebee.ArtifactPin
  alias SystemOneBumblebee.Artifacts.Prepared

  @spec prepare(ArtifactPin.t() | nil, keyword()) ::
          {:ok, Prepared.t()} | {:error, term()}
  def prepare(pin, opts \\ [])

  def prepare(nil, _opts) do
    {:ok,
     %Prepared{
       pin: nil,
       files: %{},
       manifests: %{}
     }}
  end

  def prepare(%ArtifactPin{} = pin, opts)
      when is_list(opts) do
    token =
      Keyword.get(
        opts,
        :token
      )

    force_download =
      Keyword.get(
        opts,
        :force_download,
        false
      )

    case local_root(
           Keyword.get(
             opts,
             :local_root
           )
         ) do
      {:ok, root} ->
        prepare_files(
          pin,
          token,
          force_download,
          root
        )

      {:error, _} = error ->
        error
    end
  end

  def prepare(other, _opts) do
    {:error, {:invalid_artifact_pin, other}}
  end

  defp prepare_files(
         pin,
         token,
         force_download,
         local_root
       ) do
    result =
      Enum.reduce_while(
        pin.files,
        {:ok, %{}, %{}},
        fn file, acc ->
          prepare_file_entry(
            file,
            acc,
            pin,
            token,
            force_download,
            local_root
          )
        end
      )

    finalize_prepared(
      result,
      pin
    )
  end

  defp prepare_file_entry(
         file,
         {:ok, paths, manifests},
         pin,
         token,
         force_download,
         local_root
       ) do
    case prepare_file(
           pin,
           file,
           token,
           force_download,
           local_root
         ) do
      {:ok, path, manifest_report} ->
        {:cont,
         {:ok,
          Map.put(
            paths,
            file.path,
            path
          ),
          maybe_put(
            manifests,
            file.path,
            manifest_report
          )}}

      {:error, reason} ->
        {:halt, {:error, {:artifact_prepare_failed, file.path, reason}}}
    end
  end

  defp finalize_prepared(
         {:ok, paths, manifests},
         pin
       ) do
    {:ok,
     %Prepared{
       pin: pin,
       files: paths,
       manifests: manifests
     }}
  end

  defp finalize_prepared(
         {:error, _} = error,
         _pin
       ),
       do: error

  defp prepare_file(
         pin,
         file,
         token,
         force_download,
         nil
       ) do
    download_opts = [
      repo_id: pin.repo_id,
      repo_type: pin.repo_type,
      revision: pin.revision,
      filename: file.path,
      expected_sha256: file.sha256,
      force_download: force_download
    ]

    download_opts =
      if token do
        Keyword.put(
          download_opts,
          :token,
          token
        )
      else
        download_opts
      end

    case HfHub.Download.hf_hub_download(download_opts) do
      {:ok, path} ->
        verified_path(
          path,
          file
        )

      {:error, _} = error ->
        error
    end
  end

  defp prepare_file(
         _pin,
         file,
         _token,
         _force_download,
         local_root
       ) do
    path =
      Path.join(
        local_root,
        file.path
      )

    if File.regular?(path) do
      verified_path(
        path,
        file
      )
    else
      {:error, {:local_artifact_missing, path}}
    end
  end

  defp verified_path(
         path,
         file
       ) do
    case verify_path(
           path,
           file
         ) do
      {:ok, report} ->
        {:ok, path, report}

      {:error, _} = error ->
        error
    end
  end

  defp verify_path(
         path,
         file
       ) do
    case CrucibleSafetensors.Checksum.verify_file(
           path,
           file.sha256
         ) do
      {:ok, _digest} ->
        validate_manifest(
          path,
          file
        )

      {:error, _} = error ->
        error
    end
  end

  defp validate_manifest(
         _path,
         %{tensors: nil}
       ),
       do: {:ok, nil}

  defp validate_manifest(
         path,
         %{
           tensors: tensors,
           exact_tensors: exact?
         }
       ) do
    with {:ok, report} <-
           CrucibleSafetensors.Manifest.validate_file(
             path,
             tensors,
             exact: exact?
           ),
         true <- report.valid? do
      {:ok, report}
    else
      false ->
        {:error, :tensor_manifest_mismatch}

      {:error, _} = error ->
        error
    end
  end

  defp local_root(nil),
    do: {:ok, nil}

  defp local_root(path)
       when is_binary(path) do
    {:ok, Path.expand(path)}
  end

  defp local_root(value) do
    {:error, {:invalid_local_artifact_root, value}}
  end

  defp maybe_put(
         map,
         _key,
         nil
       ),
       do: map

  defp maybe_put(
         map,
         key,
         value
       ) do
    Map.put(
      map,
      key,
      value
    )
  end
end
