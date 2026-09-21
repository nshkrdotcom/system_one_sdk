defmodule SystemOneBumblebee.Models.Laya.Preprocessing do
  @moduledoc """
  Pure Laya question/state rendering semantics ported from upstream 0.3.3.

  Tokenization is intentionally a separate stage so these deterministic strings,
  option order, type indices and budget rules can be checked against the Python
  oracle before any model math is introduced.
  """

  alias SystemOneBumblebee.Models.Laya.{Config, PythonJson}

  @mask_token "[MASK]"

  @spec serialize_state(term()) :: {:ok, String.t()} | {:error, term()}
  def serialize_state(state) when is_binary(state), do: {:ok, state}

  def serialize_state(state) do
    case PythonJson.encode(state, ensure_ascii: false) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:invalid_laya_state, reason}}
    end
  end

  @spec render_criterion(term()) :: {:ok, String.t()} | {:error, term()}
  def render_criterion(value) when is_binary(value), do: {:ok, value}

  def render_criterion(value) do
    case PythonJson.encode(value, ensure_ascii: false) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:invalid_laya_criterion, reason}}
    end
  end

  @spec normalize_question(map()) :: {:ok, map()} | {:error, term()}
  def normalize_question(question) when is_map(question) do
    type =
      question
      |> value("type")
      |> normalize_type()

    instructions = value(question, "instructions")
    criteria = value(question, "criteria")

    with {:ok, _index} <- Config.qtype_index(type),
         {:ok, instructions} <- instructions(instructions),
         {:ok, criteria} <- normalize_criteria(type, criteria) do
      {:ok, %{type: type, instructions: instructions, criteria: criteria}}
    end
  end

  def normalize_question(other), do: {:error, {:invalid_laya_question, other}}

  @spec render_question(map()) :: {:ok, String.t()} | {:error, term()}
  def render_question(question) do
    with {:ok, normalized} <- normalize_question(question) do
      {:ok, "#{normalized.type} question: #{sanitize_mask(normalized.instructions)}"}
    end
  end

  @spec render_options(map()) :: {:ok, [String.t()]} | {:error, term()}
  def render_options(question) do
    with {:ok, normalized} <- normalize_question(question) do
      do_render_options(normalized)
    end
  end

  @spec qtype(map()) :: {:ok, 0 | 1 | 2} | {:error, term()}
  def qtype(question) do
    with {:ok, normalized} <- normalize_question(question) do
      Config.qtype_index(normalized.type)
    end
  end

  @doc "Matches upstream option token capping/budget arithmetic after tokenization."
  @spec rebudget_option_ids([[term()]], pos_integer()) ::
          {:ok, [[term()]], non_neg_integer()} | {:error, term()}
  def rebudget_option_ids(option_ids, head_max_len)
      when is_list(option_ids) and is_integer(head_max_len) and head_max_len > 0 do
    initial = Enum.map(option_ids, &Enum.take(&1, 49))
    budget = head_max_len - Enum.sum(Enum.map(initial, &length/1))

    if budget < 16 do
      per = max(4, div(head_max_len - 16, max(1, length(initial))))
      trimmed = Enum.map(initial, &Enum.take(&1, per))
      {:ok, trimmed, head_max_len - Enum.sum(Enum.map(trimmed, &length/1))}
    else
      {:ok, initial, budget}
    end
  end

  def rebudget_option_ids(option_ids, head_max_len),
    do: {:error, {:invalid_laya_option_budget, option_ids, head_max_len}}

  @spec sanitize_mask(String.t()) :: String.t()
  def sanitize_mask(text) when is_binary(text), do: String.replace(text, @mask_token, " ")

  defp do_render_options(%{type: "choice", criteria: pairs}) do
    pairs
    |> Enum.reduce_while({:ok, []}, &render_choice_option/2)
    |> reverse_ok()
  end

  defp do_render_options(%{type: "score", criteria: criteria}) do
    criteria
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {criterion, index}, {:ok, acc} ->
      case render_criterion(criterion) do
        {:ok, rendered} -> {:cont, {:ok, ["level #{index}: #{rendered}" | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> reverse_ok()
  end

  defp do_render_options(%{type: "noul", criteria: criteria}) do
    false_value = criterion_value(criteria, "false")
    true_value = criterion_value(criteria, "true")

    with {:ok, false_text} <- noul_criterion(false_value, "no, the statement does not hold"),
         {:ok, true_text} <- noul_criterion(true_value, "yes, the statement holds") do
      {:ok, ["false: #{false_text}", "true: #{true_text}"]}
    end
  end

  defp render_choice_option({key, criterion}, {:ok, acc}) when criterion in [nil, ""] do
    {:cont, {:ok, [to_string(key) | acc]}}
  end

  defp render_choice_option({key, criterion}, {:ok, acc}) do
    case render_criterion(criterion) do
      {:ok, rendered} ->
        {:cont, {:ok, ["#{key}: #{rendered}" | acc]}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp normalize_criteria("choice", criteria) do
    cond do
      match?(%Jason.OrderedObject{}, criteria) ->
        {:ok, criteria.values}

      is_map(criteria) ->
        {:ok, Enum.to_list(criteria)}

      is_list(criteria) and Enum.all?(criteria, &is_binary/1) ->
        {:ok, Enum.map(criteria, &{&1, nil})}

      is_list(criteria) and Enum.all?(criteria, &match?({_, _}, &1)) ->
        {:ok, criteria}

      true ->
        {:error, {:invalid_laya_choice_criteria, criteria}}
    end
  end

  defp normalize_criteria("score", criteria) when is_list(criteria) and criteria != [],
    do: {:ok, criteria}

  defp normalize_criteria("score", criteria),
    do: {:error, {:invalid_laya_score_criteria, criteria}}

  defp normalize_criteria("noul", nil), do: {:ok, %{}}
  defp normalize_criteria("noul", criteria) when is_map(criteria), do: {:ok, criteria}
  defp normalize_criteria("noul", criteria), do: {:error, {:invalid_laya_noul_criteria, criteria}}

  defp instructions(value) when is_binary(value), do: {:ok, value}

  defp instructions(value) do
    case PythonJson.encode(value, ensure_ascii: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:invalid_laya_instructions, reason}}
    end
  end

  defp noul_criterion(value, fallback) when value in [nil, ""], do: {:ok, fallback}
  defp noul_criterion(value, _fallback), do: render_criterion(value)

  defp criterion_value(%Jason.OrderedObject{values: values}, key), do: pair_value(values, key)

  defp criterion_value(map, "false") when is_map(map),
    do: Map.get(map, "false", Map.get(map, false))

  defp criterion_value(map, "true") when is_map(map), do: Map.get(map, "true", Map.get(map, true))

  defp pair_value(values, key) do
    case Enum.find(values, fn {k, _v} -> to_string(k) == key end) do
      {_k, value} -> value
      nil -> nil
    end
  end

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type), do: type

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error

  defp value(map, key) do
    Map.get(map, key) ||
      case key do
        "type" -> Map.get(map, :type)
        "instructions" -> Map.get(map, :instructions)
        "criteria" -> Map.get(map, :criteria)
      end
  end
end
