defmodule SystemOneContracts.V1.Usage do
  @moduledoc "Token-usage metadata returned by a System One v1 provider."

  alias SystemOneContracts.Error
  alias SystemOneContracts.V1.Validation

  defstruct input_tokens: nil, output_tokens: nil

  @type t :: %__MODULE__{
          input_tokens: non_neg_integer() | nil,
          output_tokens: non_neg_integer() | nil
        }

  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(value) when is_map(value) do
    with {:ok, input} <- optional_count(Validation.value(value, "input_tokens"), "input_tokens"),
         {:ok, output} <-
           optional_count(Validation.value(value, "output_tokens"), "output_tokens") do
      {:ok, %__MODULE__{input_tokens: input, output_tokens: output}}
    end
  end

  def decode(_), do: {:error, Error.invalid_response(["usage"], "must be an object")}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = usage) do
    %{}
    |> maybe_put("input_tokens", usage.input_tokens)
    |> maybe_put("output_tokens", usage.output_tokens)
  end

  defp optional_count(nil, _key), do: {:ok, nil}
  defp optional_count(value, _key) when is_integer(value) and value >= 0, do: {:ok, value}

  defp optional_count(_value, key),
    do: {:error, Error.invalid_response(["usage", key], "must be a non-negative integer or null")}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
