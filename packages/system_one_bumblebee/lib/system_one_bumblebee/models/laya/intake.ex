defmodule SystemOneBumblebee.Models.Laya.Intake do
  @moduledoc "Inspects the staged Laya checkpoint and writes reproducible local intake evidence."

  alias CrucibleSafetensors.Checksum
  alias SystemOneBumblebee.Models.Laya.{Config, Inventory}

  @source_repo "convaiinnovations/laya"
  @source_revision "c5d78730f3493e4fe16d61507ef4b78eef7318cf"
  @upstream_code_revision "6a5819129eb220570792e417e49723d697efd76f"

  @spec analyze(Path.t()) :: {:ok, map()} | {:error, term()}
  def analyze(directory) when is_binary(directory) do
    config_path = Path.join(directory, "rl_agent_config.json")

    with true <- File.dir?(directory),
         {:ok, config} <- Config.load(config_path),
         {:ok, checkpoint} <- checkpoint(directory),
         {:ok, inventory} <- Inventory.analyze(checkpoint),
         {:ok, files} <- file_inventory(directory) do
      {:ok,
       %{
         schema_version: "system-one-bumblebee.laya-intake.v1",
         source: %{
           repository: @source_repo,
           revision: @source_revision,
           upstream_code_revision: @upstream_code_revision,
           encoder: config.encoder
         },
         config: Map.from_struct(config),
         checkpoint: %{
           relative_path: Path.relative_to(checkpoint, directory),
           tensor_inventory: inventory,
           expected_english_shape: Inventory.expected_english_shape?(inventory)
         },
         files: files
       }}
    else
      false -> {:error, {:laya_staging_directory_not_found, directory}}
      {:error, _} = error -> error
    end
  end

  @spec write(Path.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def write(directory, output_path) do
    with {:ok, report} <- analyze(directory),
         :ok <- File.mkdir_p(Path.dirname(output_path)),
         {:ok, json} <- Jason.encode(report, pretty: true),
         :ok <- File.write(output_path, json <> "\n") do
      {:ok, output_path}
    end
  end

  defp checkpoint(directory) do
    files =
      Path.wildcard(Path.join(directory, "**/*.safetensors")) |> Enum.filter(&File.regular?/1)

    case files do
      [path] -> {:ok, path}
      [] -> {:error, {:laya_checkpoint_not_found, directory}}
      many -> {:error, {:multiple_laya_checkpoints, many}}
    end
  end

  defp file_inventory(directory) do
    directory
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      case Checksum.file_sha256(path) do
        {:ok, digest} ->
          stat = File.stat!(path)
          relative = Path.relative_to(path, directory)
          {:cont, {:ok, Map.put(acc, relative, %{sha256: digest, bytes: stat.size})}}

        {:error, reason} ->
          {:halt, {:error, {:laya_hash_failed, path, reason}}}
      end
    end)
  end
end
