defmodule SystemOneContracts.V1.ModelsResponse do
  @moduledoc "Typed System One v1 model-catalog response."

  alias SystemOneContracts.Error
  alias SystemOneContracts.V1.{Model, Validation}

  @enforce_keys [:models]
  defstruct [:models, :request_id, metadata: %{}, raw: nil]

  @type t :: %__MODULE__{
          models: [Model.t()],
          request_id: String.t() | nil,
          metadata: map(),
          raw: map() | nil
        }

  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(body) when is_map(body) do
    case Validation.value(body, "models") do
      models when is_list(models) ->
        with {:ok, decoded} <- decode_models(models) do
          {:ok, %__MODULE__{models: decoded, raw: body}}
        end

      _ ->
        {:error, Error.invalid_response(["models"], "must be a list")}
    end
  end

  def decode(_), do: {:error, Error.invalid_response([], "response must be an object")}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{models: models}), do: %{"models" => Enum.map(models, &Model.to_map/1)}

  defp decode_models(models) do
    models
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {model, index}, {:ok, acc} ->
      case Model.decode(model) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, error} -> {:halt, {:error, prefix(error, index)}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp prefix(%Error{} = error, index) do
    path = ["models", Integer.to_string(index)] ++ strip_models(error.path || [])
    %{error | path: path, message: "Invalid System One response at #{inspect(path)}"}
  end

  defp strip_models(["models" | rest]), do: rest
  defp strip_models(path), do: path
end
