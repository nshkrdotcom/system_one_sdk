defmodule SystemOneBumblebee.ArtifactPin.File do
  @moduledoc "A single SHA-256-pinned file within an immutable model revision."

  @sha256_regex ~r/\A[0-9a-f]{64}\z/i

  @enforce_keys [:path, :sha256]
  defstruct [:path, :sha256, :tensors, exact_tensors: false]

  @type t :: %__MODULE__{
          path: String.t(),
          sha256: String.t(),
          tensors: map() | nil,
          exact_tensors: boolean()
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    with {:ok, path} <- path(value(attrs, :path)),
         {:ok, sha256} <- sha256(value(attrs, :sha256)),
         {:ok, tensors} <- tensors(value(attrs, :tensors)),
         {:ok, exact?} <- exact_tensors(value(attrs, :exact_tensors, false)) do
      {:ok,
       %__MODULE__{
         path: path,
         sha256: sha256,
         tensors: tensors,
         exact_tensors: exact?
       }}
    end
  end

  def new(other), do: {:error, {:invalid_artifact_file, other}}

  defp path(value) when is_binary(value) do
    path = String.trim(value)
    segments = Path.split(path)

    cond do
      path == "" -> {:error, {:invalid_artifact_path, value}}
      Path.type(path) == :absolute -> {:error, {:invalid_artifact_path, value}}
      Enum.any?(segments, &(&1 in [".", ".."])) -> {:error, {:invalid_artifact_path, value}}
      true -> {:ok, path}
    end
  end

  defp path(value), do: {:error, {:invalid_artifact_path, value}}

  defp sha256(value) when is_binary(value) do
    digest = value |> String.trim() |> strip_prefix() |> String.downcase()

    if Regex.match?(@sha256_regex, digest),
      do: {:ok, digest},
      else: {:error, {:invalid_sha256, value}}
  end

  defp sha256(value), do: {:error, {:invalid_sha256, value}}

  defp tensors(nil), do: {:ok, nil}
  defp tensors(value) when is_map(value), do: {:ok, value}
  defp tensors(value), do: {:error, {:invalid_tensor_manifest, value}}

  defp exact_tensors(value) when is_boolean(value), do: {:ok, value}
  defp exact_tensors(value), do: {:error, {:invalid_exact_tensors, value}}

  defp strip_prefix("sha256:" <> digest), do: digest
  defp strip_prefix(digest), do: digest

  defp value(attrs, key, default \\ nil)
  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end

defmodule SystemOneBumblebee.ArtifactPin do
  @moduledoc """
  Immutable Hugging Face artifact identity used by native model manifests.

  Runtime model manifests require a full 40-character commit revision and a
  SHA-256 for every required file. Mutable branch/tag names are intentionally
  rejected here; resolve them during model intake and commit the resolved pin.
  """

  alias __MODULE__.File, as: FilePin

  @commit_regex ~r/\A[0-9a-f]{40}\z/i

  @enforce_keys [:repo_id, :repo_type, :revision, :files]
  defstruct [:repo_id, :repo_type, :revision, :files]

  @type repo_type :: :model | :dataset | :space
  @type t :: %__MODULE__{
          repo_id: String.t(),
          repo_type: repo_type(),
          revision: String.t(),
          files: [FilePin.t()]
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    with {:ok, repo_id} <- nonblank(value(attrs, :repo_id), :repo_id),
         {:ok, repo_type} <- repo_type(value(attrs, :repo_type, :model)),
         {:ok, revision} <- revision(value(attrs, :revision)),
         {:ok, files} <- files(value(attrs, :files)) do
      {:ok,
       %__MODULE__{
         repo_id: repo_id,
         repo_type: repo_type,
         revision: revision,
         files: files
       }}
    end
  end

  def new(other), do: {:error, {:invalid_artifact_pin, other}}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, pin} -> pin
      {:error, reason} -> raise ArgumentError, "invalid artifact pin: #{inspect(reason)}"
    end
  end

  @spec immutable_revision?(term()) :: boolean()
  def immutable_revision?(revision) when is_binary(revision),
    do: Regex.match?(@commit_regex, revision)

  def immutable_revision?(_), do: false

  defp repo_type(type) when type in [:model, :dataset, :space], do: {:ok, type}
  defp repo_type(type), do: {:error, {:invalid_repo_type, type}}

  defp revision(value) when is_binary(value) do
    revision = String.trim(value)

    if immutable_revision?(revision),
      do: {:ok, String.downcase(revision)},
      else: {:error, {:mutable_or_invalid_revision, value}}
  end

  defp revision(value), do: {:error, {:mutable_or_invalid_revision, value}}

  defp files(files) when is_list(files) and files != [] do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      case normalize_file(file) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} ->
        normalized = Enum.reverse(reversed)
        paths = Enum.map(normalized, & &1.path)

        if length(paths) == length(Enum.uniq(paths)),
          do: {:ok, normalized},
          else: {:error, :duplicate_artifact_file}

      error ->
        error
    end
  end

  defp files(files), do: {:error, {:invalid_artifact_files, files}}

  defp normalize_file(%FilePin{} = file), do: {:ok, file}
  defp normalize_file(attrs), do: FilePin.new(attrs)

  defp nonblank(value, field) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, {field, :blank}}, else: {:ok, value}
  end

  defp nonblank(value, field), do: {:error, {field, value}}

  defp value(attrs, key, default \\ nil)
  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
