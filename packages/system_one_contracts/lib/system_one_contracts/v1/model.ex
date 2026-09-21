defmodule SystemOneContracts.V1.Model do
  @moduledoc "Provider-neutral model metadata for System One v1 discovery."

  alias SystemOneContracts.{Capabilities, Error}
  alias SystemOneContracts.V1.Validation

  @enforce_keys [:name]
  defstruct [:name, :description, :release_date, capabilities: [], metadata: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          release_date: String.t() | nil,
          capabilities: [String.t()],
          metadata: map()
        }

  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(value) when is_map(value) do
    with {:ok, name} <- required_name(Validation.value(value, "name")),
         {:ok, description} <-
           optional_string(Validation.value(value, "description"), "description"),
         {:ok, release_date} <-
           optional_string(Validation.value(value, "release_date"), "release_date"),
         {:ok, capabilities} <- decode_capabilities(Validation.value(value, "capabilities")),
         {:ok, metadata} <- decode_metadata(Validation.value(value, "metadata")) do
      {:ok,
       %__MODULE__{
         name: name,
         description: description,
         release_date: release_date,
         capabilities: capabilities,
         metadata: metadata
       }}
    end
  end

  def decode(_), do: {:error, Error.invalid_response(["models"], "model entry must be an object")}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = model) do
    %{"name" => model.name}
    |> maybe_put("description", model.description)
    |> maybe_put("release_date", model.release_date)
    |> maybe_put_list("capabilities", model.capabilities)
    |> maybe_put_map("metadata", model.metadata)
  end

  defp required_name(value) do
    case Validation.nonblank_string(value, ["models", "name"]) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, Error.invalid_response(["models", "name"], "must be nonblank")}
    end
  end

  defp optional_string(nil, _key), do: {:ok, nil}
  defp optional_string(value, _key) when is_binary(value), do: {:ok, value}

  defp optional_string(_value, key),
    do: {:error, Error.invalid_response(["models", key], "must be a string or null")}

  defp decode_capabilities(nil), do: {:ok, []}

  defp decode_capabilities(value) do
    case Capabilities.normalize(value) do
      {:ok, capabilities} -> {:ok, capabilities}
      {:error, _} ->
        {:error,
         Error.invalid_response(["models", "capabilities"], "must be capability names")}
    end
  end

  defp decode_metadata(nil), do: {:ok, %{}}

  defp decode_metadata(value) when is_map(value) and not is_struct(value) do
    case Validation.json(value, ["models", "metadata"]) do
      :ok -> {:ok, value}
      {:error, _} -> {:error, Error.invalid_response(["models", "metadata"], "must be JSON")}
    end
  end

  defp decode_metadata(_),
    do: {:error, Error.invalid_response(["models", "metadata"], "must be an object")}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp maybe_put_list(map, _key, []), do: map
  defp maybe_put_list(map, key, value), do: Map.put(map, key, value)
  defp maybe_put_map(map, _key, value) when value == %{}, do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)
end
