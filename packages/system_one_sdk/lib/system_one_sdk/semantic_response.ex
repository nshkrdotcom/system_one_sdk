defmodule SystemOneSDK.SemanticResponse do
  @moduledoc false
  alias SystemOneSDK.{
    ChoiceAnswer,
    Error,
    ExtractionAnswer,
    NoulAnswer,
    Prepared,
    ScoreAnswer,
    SystemOneResponse
  }

  def enrich(%SystemOneResponse{} = response, %Prepared{} = prepared, tolerance) do
    with {:ok, decoded} <- decode_requested_answers(response, prepared),
         {:ok, answers} <- join(decoded.answers, prepared, tolerance) do
      {:ok, %{decoded | answers: answers}}
    else
      {:error, error} ->
        {:error, Error.attach_response(error, response.raw_http_response, response.raw)}
    end
  end

  defp decode_requested_answers(response, prepared) do
    definitions = Prepared.definitions(prepared)

    Enum.reduce_while(Prepared.wire_keys(prepared), {:ok, response}, fn
      id, {:ok, %{answers: answers} = acc} when is_map_key(answers, id) ->
        {:cont, {:ok, acc}}

      id, {:ok, acc} ->
        case decode_unknown_answer(acc, id, Map.fetch!(definitions, id).type) do
          {:ok, decoded} -> {:cont, {:ok, decoded}}
          {:error, _} = error -> {:halt, error}
        end
    end)
  end

  defp decode_unknown_answer(response, id, type) do
    case {type, Map.fetch(response.unknown_answers, id)} do
      {"text", {:ok, raw}} -> promote_extraction(response, id, raw, :text)
      {"number", {:ok, raw}} -> promote_extraction(response, id, raw, :number)
      {_, {:ok, _raw}} -> {:ok, response}
      {_, :error} -> invalid(["answers", id], "requested question has no answer entry")
    end
  end

  defp promote_extraction(response, id, raw, type) do
    with {:ok, answer} <- ExtractionAnswer.decode(raw, id, type) do
      {:ok,
       %{
         response
         | answers: Map.put(response.answers, id, answer),
           unknown_answers: Map.delete(response.unknown_answers, id)
       }}
    end
  end

  defp join(answers, prepared, tolerance) do
    Enum.reduce_while(answers, {:ok, %{}}, fn {id, answer}, {:ok, acc} ->
      with {:ok, definition} <- definition(prepared, id),
           :ok <- type_matches(answer, definition.type, id),
           {:ok, enriched} <- validate(answer, definition, ["answers", id], tolerance) do
        {:ok, key} = Prepared.caller_key(prepared, id)
        {:cont, {:ok, Map.put(acc, key, %{enriched | id: key})}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp definition(prepared, id) do
    case Map.fetch(Prepared.definitions(prepared), id) do
      {:ok, definition} -> {:ok, definition}
      :error -> invalid(["answers", id], "known answer ID was not requested")
    end
  end

  defp type_matches(%NoulAnswer{}, "noul", _), do: :ok
  defp type_matches(%ChoiceAnswer{}, "choice", _), do: :ok
  defp type_matches(%ScoreAnswer{}, "score", _), do: :ok
  defp type_matches(%ExtractionAnswer{type: :text}, "text", _), do: :ok
  defp type_matches(%ExtractionAnswer{type: :number}, "number", _), do: :ok

  defp type_matches(_, _, id),
    do: invalid(["answers", id, "type"], "does not match requested question type")

  defp validate(%NoulAnswer{} = answer, _, _, _), do: {:ok, answer}
  defp validate(%ExtractionAnswer{} = answer, _, _, _), do: {:ok, answer}

  defp validate(%ChoiceAnswer{} = answer, definition, path, tolerance) do
    with :ok <- member(answer.choice, Map.keys(definition.option_keys), path ++ ["choice"]),
         :ok <-
           domain(answer.probabilities, Map.keys(definition.option_keys), path ++ ["probabilities"]),
         :ok <- distribution(answer.probabilities, path ++ ["probabilities"], tolerance) do
      {:ok,
       %{
         answer
         | choice: Map.fetch!(definition.option_keys, answer.choice),
           probabilities:
             Map.new(answer.probabilities, fn {wire, p} ->
               {Map.fetch!(definition.option_keys, wire), p}
             end),
           option_order: definition.option_order
       }}
    end
  end

  defp validate(%ScoreAnswer{} = answer, definition, path, tolerance) do
    indices = Enum.map(definition.levels, & &1.index)
    top = length(indices) - 1

    with :ok <- score_range(answer.score, top, path ++ ["score"]),
         :ok <- domain(answer.probabilities, indices, path ++ ["probabilities"]),
         :ok <- domain(answer.legend, indices, path ++ ["legend"]),
         :ok <- distribution(answer.probabilities, path ++ ["probabilities"], tolerance) do
      level = Enum.at(definition.levels, round(answer.score))
      levels = Enum.map(definition.levels, &{&1.label, Map.fetch!(answer.probabilities, &1.index)})

      {:ok,
       %{
         answer
         | level: level.index,
           label: level.label,
           description: level.description,
           levels: levels,
           rubric: definition.levels
       }}
    end
  end

  defp member(value, keys, path) do
    if value in keys, do: :ok, else: invalid(path, "selected option was not requested")
  end

  defp domain(values, expected, path) do
    if MapSet.new(Map.keys(values)) == MapSet.new(expected),
      do: :ok,
      else: invalid(path, "key domain differs from the question rubric")
  end

  defp distribution(values, path, tolerance) do
    sum = Enum.sum(Map.values(values))

    if abs(sum - 1.0) <= tolerance + 1.0e-12,
      do: :ok,
      else: invalid(path, "probabilities must sum to 1 within the configured tolerance")
  end

  defp score_range(score, top, path) do
    if score >= 0 and score <= top,
      do: :ok,
      else: invalid(path, "score is outside the requested level range")
  end

  defp invalid(path, reason), do: {:error, Error.invalid_response(path, reason)}
end
