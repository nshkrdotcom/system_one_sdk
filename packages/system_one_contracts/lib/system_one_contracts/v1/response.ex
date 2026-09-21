defmodule SystemOneContracts.V1.Response do
  @moduledoc "Typed System One v1 inference response with forward-compatible answer preservation."

  alias SystemOneContracts.Error
  alias SystemOneContracts.V1.{Usage, Validation}

  @enforce_keys [:model, :usage, :answers]
  defstruct [:model, :usage, :answers, :request_id, metadata: %{}, raw: nil]

  @type t :: %__MODULE__{
          model: String.t(),
          usage: Usage.t(),
          answers: %{String.t() => map()},
          request_id: String.t() | nil,
          metadata: map(),
          raw: map() | nil
        }

  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(body) when is_map(body) do
    with {:ok, model} <- required_model(Validation.value(body, "model")),
         {:ok, usage} <- Usage.decode(Validation.value(body, "usage")),
         {:ok, answers} <- decode_answers(Validation.value(body, "answers")) do
      {:ok, %__MODULE__{model: model, usage: usage, answers: answers, raw: body}}
    end
  end

  def decode(_), do: {:error, Error.invalid_response([], "response must be an object")}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = response) do
    %{
      "model" => response.model,
      "usage" => Usage.to_map(response.usage),
      "answers" => response.answers
    }
  end

  defp required_model(value) do
    case Validation.nonblank_string(value, ["model"]) do
      {:ok, model} -> {:ok, model}
      :error -> {:error, Error.invalid_response(["model"], "must be a nonblank UTF-8 string")}
    end
  end

  defp decode_answers(answers) when is_map(answers) and not is_struct(answers) do
    Enum.reduce_while(answers, {:ok, %{}}, fn
      {key, answer}, {:ok, acc} when is_binary(key) or is_atom(key) ->
        wire_key = to_string(key)

        cond do
          String.trim(wire_key) == "" or not String.valid?(wire_key) or
              Map.has_key?(acc, wire_key) ->
            {:halt,
             {:error,
              Error.invalid_response(["answers"], "contains an invalid or duplicate key")}}

          true ->
            case validate_answer(answer, wire_key) do
              :ok -> {:cont, {:ok, Map.put(acc, wire_key, answer)}}
              {:error, _} = error -> {:halt, error}
            end
        end

      _entry, _acc ->
        {:halt,
         {:error, Error.invalid_response(["answers"], "answer keys must be strings")}}
    end)
  end

  defp decode_answers(_), do: {:error, Error.invalid_response(["answers"], "must be an object")}

  defp validate_answer(answer, key) when is_map(answer) do
    case Validation.value(answer, "type") do
      "noul" -> validate_noul(answer, key)
      "choice" -> validate_choice(answer, key)
      "score" -> validate_score(answer, key)
      type when is_binary(type) and type != "" -> :ok
      _ -> {:error, Error.invalid_response(["answers", key, "type"], "must be nonblank")}
    end
  end

  defp validate_answer(_answer, key),
    do: {:error, Error.invalid_response(["answers", key], "must be an object")}

  defp validate_noul(answer, key) do
    if Validation.probability(Validation.value(answer, "noul")) == :ok,
      do: :ok,
      else: {:error, Error.invalid_response(["answers", key, "noul"], "must be in [0, 1]")}
  end

  defp validate_choice(answer, key) do
    choice = Validation.value(answer, "choice")
    confidence = Validation.value(answer, "confidence")
    probabilities = Validation.value(answer, "probabilities")

    cond do
      not is_binary(choice) or choice == "" ->
        {:error, Error.invalid_response(["answers", key, "choice"], "must be nonblank")}

      Validation.probability(confidence) != :ok ->
        {:error, Error.invalid_response(["answers", key, "confidence"], "must be in [0, 1]")}

      true ->
        probability_map(probabilities, ["answers", key, "probabilities"], :string)
    end
  end

  defp validate_score(answer, key) do
    score = Validation.value(answer, "score")
    confidence = Validation.value(answer, "confidence")
    legend = Validation.value(answer, "legend")
    probabilities = Validation.value(answer, "probabilities")

    cond do
      not is_number(score) ->
        {:error, Error.invalid_response(["answers", key, "score"], "must be numeric")}

      Validation.probability(confidence) != :ok ->
        {:error, Error.invalid_response(["answers", key, "confidence"], "must be in [0, 1]")}

      not is_map(legend) ->
        {:error, Error.invalid_response(["answers", key, "legend"], "must be an object")}

      true ->
        probability_map(probabilities, ["answers", key, "probabilities"], :integer)
    end
  end

  defp probability_map(map, path, key_type) when is_map(map) and map_size(map) > 0 do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      if valid_probability_key?(key, key_type) and Validation.probability(value) == :ok,
        do: {:cont, :ok},
        else: {:halt, {:error, Error.invalid_response(path, "contains an invalid probability")}}
    end)
  end

  defp probability_map(_map, path, _key_type),
    do: {:error, Error.invalid_response(path, "must be a non-empty object")}

  defp valid_probability_key?(key, :string), do: is_binary(key) or is_atom(key) or is_integer(key)
  defp valid_probability_key?(key, :integer) when is_integer(key), do: true

  defp valid_probability_key?(key, :integer) when is_binary(key) do
    case Integer.parse(key) do
      {_value, ""} -> true
      _ -> false
    end
  end

  defp valid_probability_key?(_key, :integer), do: false
end
