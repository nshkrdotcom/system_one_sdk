defmodule SystemOneSDK.ExtractionAnswer do
  @moduledoc """
  A typed text or numeric value extracted by a System One provider.

  `value` is `nil` when the provider returned an explicit null. `span` holds the
  provider's source offsets, when supplied. Offset units and the source they
  refer to are defined by the provider. Some providers supply a candidate span
  even when the value is null. `confidence` and `null_probability` are optional.
  The original answer is available in `raw`.
  """

  alias SystemOneSDK.Error

  @enforce_keys [:type, :value]
  defstruct [:type, :value, :span, :confidence, :null_probability, :id, :raw]

  @type t :: %__MODULE__{
          type: :text | :number,
          value: String.t() | number() | nil,
          span: {non_neg_integer(), non_neg_integer()} | nil,
          confidence: number() | nil,
          null_probability: number() | nil,
          id: atom() | String.t() | nil,
          raw: map() | nil
        }

  @doc false
  @spec decode(term(), String.t(), :text | :number) :: {:ok, t()} | {:error, Error.t()}
  def decode(raw, name, type) when is_map(raw) do
    path = ["answers", name]

    with :ok <- check_type(raw, type, path ++ ["type"]),
         :ok <- check_status(raw, :valid, path ++ ["valid"]),
         :ok <- check_status(raw, :complete, path ++ ["complete"]),
         {:ok, value} <- decode_value(raw, type, path ++ ["value"]),
         {:ok, span} <- decode_span(raw, path ++ ["span"]),
         {:ok, confidence} <- optional_probability(raw, :confidence, path ++ ["confidence"]),
         {:ok, null_probability} <- optional_probability(raw, :p_null, path ++ ["p_null"]) do
      {:ok,
       %__MODULE__{
         id: name,
         type: type,
         value: value,
         span: span,
         confidence: confidence,
         null_probability: null_probability,
         raw: raw
       }}
    end
  end

  def decode(raw, name, _type), do: {:error, Error.response_validation(["answers", name], raw)}

  defp check_type(raw, type, path) do
    if field(raw, :type) == Atom.to_string(type),
      do: :ok,
      else: {:error, Error.invalid_response(path, "does not match requested question type")}
  end

  defp check_status(raw, key, path) do
    case field(raw, key, true) do
      true -> :ok
      false -> {:error, Error.invalid_response(path, "provider reported failed extraction")}
      _ -> {:error, Error.response_validation(path, raw)}
    end
  end

  defp decode_value(raw, type, path) do
    case {type, field(raw, :value, :missing)} do
      {_, nil} ->
        {:ok, nil}

      {:text, value} when is_binary(value) ->
        if String.valid?(value),
          do: {:ok, value},
          else: {:error, Error.response_validation(path, raw)}

      {:number, value} when is_number(value) ->
        {:ok, value}

      _ ->
        {:error, Error.response_validation(path, raw)}
    end
  end

  defp decode_span(raw, path) do
    case field(raw, :span) do
      nil ->
        {:ok, nil}

      [first, last] when is_integer(first) and is_integer(last) and first >= 0 and last >= first ->
        {:ok, {first, last}}

      _ ->
        {:error, Error.response_validation(path, raw)}
    end
  end

  defp optional_probability(raw, key, path) do
    case field(raw, key) do
      nil -> {:ok, nil}
      value when is_number(value) and value >= 0 and value <= 1 -> {:ok, value}
      _ -> {:error, Error.response_validation(path, raw)}
    end
  end

  defp field(raw, key, default \\ nil),
    do: Map.get(raw, Atom.to_string(key), Map.get(raw, key, default))
end
