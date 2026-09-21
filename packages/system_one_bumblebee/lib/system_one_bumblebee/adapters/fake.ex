defmodule SystemOneBumblebee.Adapters.Fake do
  @moduledoc "Deterministic offline adapter used to test provider/runtime contracts without model downloads."

  @behaviour SystemOneBumblebee.ModelAdapter

  alias SystemOneContracts.Error
  alias SystemOneContracts.V1.{Response, Usage}

  @impl true
  def capabilities(_manifest), do: SystemOneContracts.Capabilities.core()

  @impl true
  def load(manifest, _artifacts, profile, _opts) do
    {:ok, %{model: manifest.name, profile: profile.name}}
  end

  @impl true
  def infer(runtime, request, _opts) do
    request.questions
    |> Enum.reduce_while({:ok, %{}}, fn {key, question}, {:ok, answers} ->
      case answer(question) do
        {:ok, value} -> {:cont, {:ok, Map.put(answers, key, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, answers} ->
        {:ok,
         %Response{
           model: runtime.model,
           usage: %Usage{input_tokens: 0, output_tokens: 0},
           answers: answers,
           metadata: %{"adapter" => "fake"}
         }}

      error ->
        error
    end
  end

  defp answer(question) do
    case value(question, "type") do
      "noul" ->
        {:ok, %{"type" => "noul", "noul" => 0.5}}

      "choice" ->
        choice_answer(value(question, "criteria"))

      "score" ->
        score_answer(value(question, "criteria"))

      type ->
        {:error,
         %Error{
           type: :unsupported,
           message: "Fake adapter does not implement this question type",
           details: %{question_type: type}
         }}
    end
  end

  defp choice_answer(criteria) do
    pairs = ordered_pairs(criteria)

    case pairs do
      [] ->
        {:error, Error.invalid_request(["criteria"], "choice criteria must not be empty")}

      [{selected, _} | _] ->
        probabilities =
          pairs
          |> Enum.with_index()
          |> Map.new(fn {{key, _value}, index} -> {to_string(key), if(index == 0, do: 1.0, else: 0.0)} end)

        {:ok,
         %{
           "type" => "choice",
           "choice" => to_string(selected),
           "confidence" => 1.0,
           "probabilities" => probabilities
         }}
    end
  end

  defp score_answer(criteria) do
    labels = score_labels(criteria)

    if labels == [] do
      {:error, Error.invalid_request(["criteria"], "score criteria must not be empty")}
    else
      legend = labels |> Enum.with_index() |> Map.new(fn {label, index} -> {to_string(index), label} end)

      probabilities =
        labels
        |> Enum.with_index()
        |> Map.new(fn {_label, index} -> {to_string(index), if(index == 0, do: 1.0, else: 0.0)} end)

      {:ok,
       %{
         "type" => "score",
         "score" => 0.0,
         "confidence" => 1.0,
         "legend" => legend,
         "probabilities" => probabilities
       }}
    end
  end

  defp score_labels(criteria) when is_list(criteria) do
    Enum.map(criteria, &to_string/1)
  end

  defp score_labels(criteria) do
    criteria |> ordered_pairs() |> Enum.map(fn {_key, label} -> to_string(label) end)
  end

  defp ordered_pairs(%Jason.OrderedObject{values: values}), do: values

  defp ordered_pairs(map) when is_map(map) and not is_struct(map) do
    map |> Map.to_list() |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
  end

  defp ordered_pairs(list) when is_list(list) do
    if Enum.all?(list, &match?({_, _}, &1)), do: list, else: []
  end

  defp ordered_pairs(_), do: []

  defp value(%Jason.OrderedObject{values: values}, key) do
    case List.keyfind(values, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp value(map, key) when is_map(map) do
    Map.get(map, key) ||
      case key do
        "type" -> Map.get(map, :type)
        "criteria" -> Map.get(map, :criteria)
        _ -> nil
      end
  end
end
