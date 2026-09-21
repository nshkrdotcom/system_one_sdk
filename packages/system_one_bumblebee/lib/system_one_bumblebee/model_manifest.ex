defmodule SystemOneBumblebee.ModelManifest do
  @moduledoc "Registered native model identity and adapter configuration."

  alias SystemOneBumblebee.ArtifactPin
  alias SystemOneContracts.{Capabilities, Error}
  alias SystemOneContracts.V1.Model

  @enforce_keys [:name, :adapter, :capabilities]
  defstruct [
    :name,
    :adapter,
    :pin,
    :description,
    :release_date,
    aliases: [],
    capabilities: [],
    metadata: %{},
    adapter_options: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          adapter: module(),
          pin: ArtifactPin.t() | nil,
          description: String.t() | nil,
          release_date: String.t() | nil,
          aliases: [String.t()],
          capabilities: [String.t()],
          metadata: map(),
          adapter_options: keyword()
        }

  @spec new(String.t(), map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(name, attrs) when (is_map(attrs) or is_list(attrs)) and is_binary(name) do
    with {:ok, name} <- nonblank(name, :name),
         {:ok, adapter} <- adapter(value(attrs, :adapter)),
         {:ok, pin} <- pin(value(attrs, :pin)),
         {:ok, aliases} <- aliases(value(attrs, :aliases, []), name),
         {:ok, capabilities} <- capabilities(value(attrs, :capabilities, Capabilities.core())),
         {:ok, metadata} <- metadata(value(attrs, :metadata, %{})),
         {:ok, adapter_options} <- adapter_options(value(attrs, :adapter_options, [])),
         {:ok, description} <- optional_string(value(attrs, :description), :description),
         {:ok, release_date} <- optional_string(value(attrs, :release_date), :release_date) do
      {:ok,
       %__MODULE__{
         name: name,
         adapter: adapter,
         pin: pin,
         description: description,
         release_date: release_date,
         aliases: aliases,
         capabilities: capabilities,
         metadata: metadata,
         adapter_options: adapter_options
       }}
    end
  end

  def new(name, attrs), do: {:error, {:invalid_model_manifest, name, attrs}}

  @spec to_contract_model(t()) :: Model.t()
  def to_contract_model(%__MODULE__{} = manifest) do
    artifact_metadata =
      case manifest.pin do
        nil -> %{}
        pin -> %{"repo_id" => pin.repo_id, "revision" => pin.revision}
      end

    metadata =
      manifest.metadata
      |> Map.put_new("adapter", inspect(manifest.adapter))
      |> maybe_put("aliases", manifest.aliases)
      |> maybe_put("artifact", artifact_metadata)

    %Model{
      name: manifest.name,
      description: manifest.description,
      release_date: manifest.release_date,
      capabilities: manifest.capabilities,
      metadata: metadata
    }
  end

  @spec supports_request?(t(), SystemOneContracts.V1.Request.t()) ::
          :ok | {:error, Error.t()}
  def supports_request?(%__MODULE__{} = manifest, request) do
    missing =
      request.questions
      |> Enum.map(fn {_key, question} -> capability_for_question(question) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in manifest.capabilities))

    if missing == [] do
      :ok
    else
      {:error,
       %Error{
         type: :unsupported,
         message: "Model does not support requested System One question types",
         details: %{model: manifest.name, missing_capabilities: missing}
       }}
    end
  end

  defp capability_for_question(question) do
    case map_value(question, "type") do
      "noul" -> "question:noul"
      "choice" -> "question:choice"
      "score" -> "question:score"
      _ -> nil
    end
  end

  defp adapter(module) when is_atom(module) do
    callbacks = [load: 4, infer: 3, capabilities: 1]

    if Code.ensure_loaded?(module) and
         Enum.all?(callbacks, fn {name, arity} -> function_exported?(module, name, arity) end) do
      {:ok, module}
    else
      {:error, {:invalid_model_adapter, module}}
    end
  end

  defp adapter(value), do: {:error, {:invalid_model_adapter, value}}

  defp pin(nil), do: {:ok, nil}
  defp pin(%ArtifactPin{} = pin), do: {:ok, pin}
  defp pin(value), do: ArtifactPin.new(value)

  defp aliases(values, name) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case nonblank(value, :alias) do
        {:ok, alias_name} -> {:cont, {:ok, [alias_name | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} ->
        normalized = reversed |> Enum.reverse() |> Enum.uniq()
        if name in normalized, do: {:error, :model_name_cannot_be_alias}, else: {:ok, normalized}

      error ->
        error
    end
  end

  defp aliases(value, _name), do: {:error, {:invalid_aliases, value}}

  defp capabilities(value) do
    case Capabilities.normalize(value) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, reason} -> {:error, {:invalid_capabilities, reason}}
    end
  end

  defp metadata(value) when is_map(value) and not is_struct(value) do
    case Jason.encode(value) do
      {:ok, _} -> {:ok, value}
      {:error, reason} -> {:error, {:invalid_metadata, reason}}
    end
  end

  defp metadata(value), do: {:error, {:invalid_metadata, value}}

  defp adapter_options(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: {:ok, value},
      else: {:error, {:invalid_adapter_options, value}}
  end

  defp adapter_options(value), do: {:error, {:invalid_adapter_options, value}}

  defp optional_string(nil, _key), do: {:ok, nil}
  defp optional_string(value, _key) when is_binary(value), do: {:ok, value}
  defp optional_string(value, key), do: {:error, {key, value}}

  defp nonblank(value, field) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, {field, :blank}}, else: {:ok, value}
  end

  defp nonblank(value, field), do: {:error, {field, value}}

  defp map_value(%Jason.OrderedObject{values: values}, key) do
    case List.keyfind(values, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp map_value(map, "type") when is_map(map), do: Map.get(map, "type", Map.get(map, :type))
  defp map_value(_map, _key), do: nil

  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, value) when value == %{}, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp value(attrs, key, default \\ nil)
  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
