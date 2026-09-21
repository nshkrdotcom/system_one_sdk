defmodule SystemOneBumblebee.Models.Laya.Output do
  @moduledoc "Translates Laya option logits and action probabilities into canonical System One answers."

  alias SystemOneBumblebee.Models.Laya.{Calibration, Config, Preprocessing}

  @spec answer(map(), [number()], number(), Config.t()) :: {:ok, map()} | {:error, term()}
  def answer(question, logits, act_probability, %Config{} = config) do
    with {:ok, normalized} <- Preprocessing.normalize_question(question),
         {:ok, probabilities} <- Calibration.probabilities(logits, config, normalized.type),
         true <- valid_size?(normalized, probabilities) do
      build(normalized, probabilities, act_probability)
    else
      false -> {:error, :laya_probability_count_mismatch}
      {:error, _} = error -> error
    end
  end

  defp build(%{type: "choice", criteria: pairs}, probabilities, act_probability) do
    keys = Enum.map(pairs, fn {key, _} -> to_string(key) end)
    selected = keys |> Enum.zip(probabilities) |> Enum.max_by(&elem(&1, 1)) |> elem(0)

    {:ok,
     %{
       "type" => "choice",
       "choice" => selected,
       "probabilities" => map_probabilities(keys, probabilities),
       "confidence" => round4(Calibration.confidence(probabilities)),
       "action" => %{"act_probability" => round4(act_probability)}
     }}
  end

  defp build(%{type: "score", criteria: criteria}, probabilities, act_probability) do
    score =
      probabilities |> Enum.with_index() |> Enum.reduce(0.0, fn {p, i}, acc -> acc + p * i end)

    keys = Enum.map(0..(length(criteria) - 1), &Integer.to_string/1)

    {:ok,
     %{
       "type" => "score",
       "score" => round4(score),
       "legend" =>
         criteria
         |> Enum.with_index()
         |> Map.new(fn {value, i} -> {Integer.to_string(i), value} end),
       "probabilities" => map_probabilities(keys, probabilities),
       "confidence" => round4(Calibration.confidence(probabilities)),
       "action" => %{"act_probability" => round4(act_probability)}
     }}
  end

  defp build(%{type: "noul"}, [p_false, p_true], act_probability) do
    {:ok,
     %{
       "type" => "noul",
       "noul" => round4(p_true),
       "confidence" => round4(max(p_true, p_false)),
       "action" => %{"act_probability" => round4(act_probability)}
     }}
  end

  defp valid_size?(%{type: "choice", criteria: criteria}, probabilities),
    do: length(criteria) == length(probabilities)

  defp valid_size?(%{type: "score", criteria: criteria}, probabilities),
    do: length(criteria) == length(probabilities)

  defp valid_size?(%{type: "noul"}, probabilities), do: length(probabilities) == 2

  defp map_probabilities(keys, values) do
    keys |> Enum.zip(values) |> Map.new(fn {key, value} -> {key, round4(value)} end)
  end

  defp round4(value) when is_number(value), do: Float.round(value * 1.0, 4)
end
