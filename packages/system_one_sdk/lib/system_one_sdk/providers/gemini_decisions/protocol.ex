defmodule SystemOneSDK.Providers.GeminiDecisions.Protocol do
  @moduledoc """
  Wire protocol encoder and response decoder for the Gemini Decisions API
  (`gemini-decision-1`), supporting both LiteLLM's unified `/v1/decisions` format
  and Google's native `/v1beta/decisions` (or `/gemini/v1beta/decisions`
  passthrough) format.
  """

  alias SystemOneSDK.{
    ChoiceAnswer,
    Error,
    NoulAnswer,
    Prepared,
    ScoreAnswer,
    SystemOneResponse,
    Usage
  }

  @type mode :: :unified | :native
  @type auth_mode :: :bearer | :x_goog_api_key | :none

  @prob_epsilon 1.0e-6

  @noul_boolean_keys [
    "noul",
    "decision",
    "answer",
    "value",
    "result",
    "predicate",
    "probability"
  ]

  @noul_polarity_keys [
    "noul",
    "probability",
    "predicate",
    "decision",
    "answer",
    "value",
    "result"
  ]

  @noul_numeric_keys @noul_polarity_keys ++ ["confidence"]

  @doc """
  Builds authentication headers for the given `api_key` and `auth_mode`.
  """
  @spec auth_headers(String.t() | nil, auth_mode()) :: %{optional(String.t()) => String.t()}
  def auth_headers(_api_key, :none), do: %{}
  def auth_headers(nil, _auth_mode), do: %{}
  def auth_headers("", _auth_mode), do: %{}
  def auth_headers(api_key, :bearer), do: %{"Authorization" => "Bearer #{api_key}"}
  def auth_headers(api_key, :x_goog_api_key), do: %{"x-goog-api-key" => api_key}

  @doc """
  Encodes an input `state` and compiled `%SystemOneSDK.Prepared{}` contract into
  a Gemini Decisions JSON-serializable map for either `:unified` (`/v1/decisions`)
  or `:native` (`/v1beta/decisions`) endpoints, raising `SystemOneSDK.Error` if
  `state` cannot be JSON-encoded.
  """
  @spec encode_request(term(), Prepared.t(), String.t(), mode()) :: map()
  def encode_request(state, %Prepared{} = prepared, model, mode)
      when mode in [:unified, :native] do
    case encode_request_safe(state, prepared, model, mode) do
      {:ok, payload} -> payload
      {:error, %Error{} = err} -> raise err
    end
  end

  @doc """
  Safely encodes an input `state` and compiled `%SystemOneSDK.Prepared{}`
  contract, returning `{:error, %SystemOneSDK.Error{type: :invalid_request}}`
  instead of raising on unencodable `state` values (tuples, PIDs, non-UTF-8
  binaries, or custom structs).
  """
  @spec encode_request_safe(term(), Prepared.t(), String.t(), mode()) ::
          {:ok, map()} | {:error, Error.t()}
  def encode_request_safe(state, %Prepared{} = prepared, model, mode)
      when mode in [:unified, :native] do
    with {:ok, input} <- encode_input_safe(state) do
      {:ok,
       %{
         "model" => model,
         "input" => input,
         "questions" => encode_questions(prepared, mode)
       }}
    end
  end

  defp encode_input_safe(state) when is_binary(state) do
    if String.valid?(state) do
      {:ok, state}
    else
      {:error,
       Error.invalid_request(
         ["state"],
         "input state binary must be valid UTF-8",
         %{reason: :invalid_utf8_input}
       )}
    end
  end

  defp encode_input_safe(state) do
    case Jason.encode(state) do
      {:ok, encoded} ->
        {:ok, encoded}

      {:error, reason} ->
        {:error,
         Error.invalid_request(
           ["state"],
           "failed to JSON-encode input state: #{Exception.message(reason)}",
           %{reason: reason}
         )}
    end
  rescue
    err in [Jason.EncodeError, Protocol.UndefinedError] ->
      {:error,
       Error.invalid_request(
         ["state"],
         "failed to JSON-encode input state: #{Exception.message(err)}",
         %{reason: err}
       )}
  end

  defp encode_questions(%Prepared{} = prepared, :unified) do
    Enum.map(prepared.ordered_keys, fn caller_key ->
      wire_key = to_string(caller_key)
      defn = Map.fetch!(prepared.definitions, wire_key)
      encode_unified_question(wire_key, defn)
    end)
  end

  defp encode_questions(%Prepared{} = prepared, :native) do
    Map.new(prepared.ordered_keys, fn caller_key ->
      wire_key = to_string(caller_key)
      defn = Map.fetch!(prepared.definitions, wire_key)
      {wire_key, encode_native_question(defn)}
    end)
  end

  defp encode_unified_question(name, %{type: "noul", wire: wire} = defn) do
    %{"type" => "predicate", "name" => name}
    |> maybe_put_instructions(merge_noul_instructions(wire["instructions"], defn[:criteria]))
  end

  defp encode_unified_question(name, %{type: "choice", wire: wire, criteria: criteria} = defn) do
    criteria_map = Map.new(criteria, fn {k, desc} -> {to_string(k), desc} end)

    choices =
      case Map.get(defn, :option_order) do
        order when is_list(order) and order != [] ->
          Enum.map(order, fn k ->
            val = to_string(k)
            %{"value" => val, "description" => Map.fetch!(criteria_map, val)}
          end)

        _ ->
          Enum.map(criteria, fn {k, desc} ->
            %{"value" => to_string(k), "description" => desc}
          end)
      end

    %{"type" => "choice", "name" => name, "choices" => choices}
    |> maybe_put_instructions(wire["instructions"])
  end

  defp encode_unified_question(name, %{type: "score", wire: wire, levels: levels}) do
    encoded_levels =
      Enum.map(levels, fn lvl ->
        %{"label" => lvl.label, "description" => lvl.description}
      end)

    %{"type" => "score", "name" => name, "levels" => encoded_levels}
    |> maybe_put_instructions(wire["instructions"])
  end

  defp encode_native_question(%{type: "noul", wire: wire} = defn) do
    %{"type" => "noul"}
    |> maybe_put_instructions(merge_noul_instructions(wire["instructions"], defn[:criteria]))
  end

  defp encode_native_question(%{type: "choice", wire: wire, criteria: criteria}) do
    criteria_map = Map.new(criteria, fn {k, desc} -> {to_string(k), desc} end)

    %{"type" => "choice", "criteria" => criteria_map}
    |> maybe_put_instructions(wire["instructions"])
  end

  defp encode_native_question(%{type: "score", wire: wire, levels: levels}) do
    encoded_criteria = Enum.map(levels, & &1.description)

    %{"type" => "score", "criteria" => encoded_criteria}
    |> maybe_put_instructions(wire["instructions"])
  end

  defp maybe_put_instructions(map, nil), do: map
  defp maybe_put_instructions(map, instructions), do: Map.put(map, "instructions", instructions)

  defp merge_noul_instructions(instructions, criteria) when criteria in [nil, [], %{}],
    do: instructions

  defp merge_noul_instructions(instructions, criteria) do
    formatted = Enum.map_join(criteria, "\n", fn {k, v} -> "#{k}: #{v}" end)

    case instructions do
      nil -> formatted
      "" -> formatted
      inst -> "#{inst}\n#{formatted}"
    end
  end

  @doc """
  Decodes a Gemini Decisions API JSON response body (unified `/v1/decisions`,
  native `/v1beta/decisions`, or single-question flat format) into a
  `%SystemOneSDK.SystemOneResponse{}`.
  """
  @spec decode_response(term(), Prepared.t(), String.t()) ::
          {:ok, SystemOneResponse.t()} | {:error, Error.t()}
  def decode_response(body, %Prepared{} = prepared, default_model)
      when is_map(body) and not is_struct(body) do
    model =
      case body["model"] do
        m when is_binary(m) and m != "" -> m
        _ -> default_model
      end

    usage = decode_usage(body)

    with {:ok, raw_answers, source} <- extract_raw_answers(body, prepared),
         {:ok, answers} <- normalize_answers(raw_answers, prepared, source) do
      {:ok,
       %SystemOneResponse{
         model: model,
         usage: usage,
         answers: answers,
         raw: body,
         prepared_fingerprint: prepared.fingerprint
       }}
    end
  end

  def decode_response(body, _prepared, _default_model) do
    {:error,
     Error.invalid_response(
       ["response"],
       "expected Gemini Decisions response to be a JSON object",
       body
     )}
  end

  defp decode_usage(body) do
    candidates =
      [body["usage"], body["usage_metadata"], body["usageMetadata"], body]
      |> Enum.filter(&(is_map(&1) and not is_struct(&1) and map_size(&1) > 0))

    input_tokens =
      find_usage_tokens(candidates, [
        "input_tokens",
        "total_input_tokens",
        "prompt_tokens",
        "prompt_token_count",
        "totalInputTokens",
        "promptTokenCount",
        "inputTokens"
      ])

    output_tokens =
      find_usage_tokens(candidates, [
        "output_tokens",
        "total_output_tokens",
        "completion_tokens",
        "candidates_token_count",
        "totalOutputTokens",
        "candidatesTokenCount",
        "outputTokens"
      ])

    %Usage{input_tokens: input_tokens, output_tokens: output_tokens}
  end

  defp find_usage_tokens(candidates, keys) do
    Enum.find_value(candidates, &find_map_token(&1, keys))
  end

  defp find_map_token(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, val} when is_integer(val) -> val
        _ -> nil
      end
    end)
  end

  defp extract_raw_answers(%{"error" => err} = body, _prepared) when not is_nil(err) do
    {:error,
     %Error{
       type: :api_error,
       message: "Gemini Decisions upstream error: #{inspect(err)}",
       body: body,
       details: %{provider: :gemini_decisions, error: err}
     }}
  end

  defp extract_raw_answers(
         %{"answers" => [item]},
         %Prepared{ordered_keys: [single_key]}
       )
       when is_map(item) and not is_struct(item) and not is_map_key(item, "name") do
    {:ok, %{to_string(single_key) => item}, :answers}
  end

  defp extract_raw_answers(%{"answers" => list} = body, _prepared) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, %{}}, &put_list_answer_entry(&1, &2, body))
    |> case do
      {:ok, by_name} -> {:ok, by_name, :answers}
      {:error, _} = err -> err
    end
  end

  defp extract_raw_answers(%{"answers" => map} = body, _prepared)
       when is_map(map) and not is_struct(map) do
    map
    |> Enum.reduce_while({:ok, %{}}, &put_map_answer_entry(&1, &2, body))
    |> case do
      {:ok, by_key} -> {:ok, by_key, :answers}
      {:error, _} = err -> err
    end
  end

  defp extract_raw_answers(body, %Prepared{ordered_keys: [single_key]} = prepared)
       when not is_map_key(body, "answers") do
    wire_key = to_string(single_key)
    defn = Map.fetch!(prepared.definitions, wire_key)

    if has_flat_decision_fields?(body, defn.type) do
      {:ok, %{wire_key => body}, :flat}
    else
      {:error,
       Error.invalid_response(["answers"], "Gemini Decisions response missing 'answers'", body)}
    end
  end

  defp extract_raw_answers(body, _prepared) do
    {:error,
     Error.invalid_response(["answers"], "Gemini Decisions response missing 'answers'", body)}
  end

  defp put_list_answer_entry(
         %{"name" => name} = item,
         {:ok, acc},
         body
       )
       when (is_binary(name) and name != "") or
              (is_atom(name) and not is_nil(name) and not is_boolean(name)) or
              is_integer(name) do
    wire_name = to_string(name)

    if Map.has_key?(acc, wire_name) do
      {:halt,
       invalid_response_error(
         ["answers", wire_name],
         "duplicate answer entry #{inspect(wire_name)} in Gemini Decisions 'answers' list",
         :duplicate_answer_entry,
         %{name: wire_name, item: item},
         body
       )}
    else
      {:cont, {:ok, Map.put(acc, wire_name, item)}}
    end
  end

  defp put_list_answer_entry(item, _acc, body) do
    {:halt,
     invalid_response_error(
       ["answers"],
       "invalid answer entry in Gemini Decisions 'answers' list",
       :invalid_answer_entry,
       %{item: item},
       body
     )}
  end

  defp put_map_answer_entry({k, v}, {:ok, acc}, body)
       when (is_binary(k) and k != "") or
              (is_atom(k) and not is_nil(k) and not is_boolean(k)) or
              is_integer(k) do
    wire_key = to_string(k)

    if Map.has_key?(acc, wire_key) do
      {:halt,
       invalid_response_error(
         ["answers", wire_key],
         "duplicate answer key #{inspect(wire_key)} in Gemini Decisions 'answers' map",
         :duplicate_answer_key,
         %{key: k},
         body
       )}
    else
      {:cont, {:ok, Map.put(acc, wire_key, v)}}
    end
  end

  defp put_map_answer_entry({k, _v}, _acc, body) do
    {:halt,
     invalid_response_error(
       ["answers"],
       "invalid answer key in Gemini Decisions 'answers' map",
       :invalid_answer_key,
       %{key: k},
       body
     )}
  end

  defp has_flat_decision_fields?(body, "noul") do
    not Map.has_key?(body, "choice") and
      not Map.has_key?(body, "score") and
      body["type"] in [nil, "noul", "predicate"] and
      Enum.any?(
        [
          "noul",
          "probability",
          "confidence",
          "decision",
          "answer",
          "value",
          "result",
          "predicate"
        ],
        &Map.has_key?(body, &1)
      )
  end

  defp has_flat_decision_fields?(body, "choice") do
    Map.has_key?(body, "choice") and
      not Map.has_key?(body, "noul") and
      not Map.has_key?(body, "score") and
      body["type"] in [nil, "choice"]
  end

  defp has_flat_decision_fields?(body, "score") do
    (Map.has_key?(body, "score") or body["type"] == "score" or
       has_flat_score_probabilities?(body)) and
      not Map.has_key?(body, "noul") and
      not Map.has_key?(body, "choice") and
      body["type"] in [nil, "score"]
  end

  defp has_flat_decision_fields?(_body, _type), do: false

  defp has_flat_score_probabilities?(%{"probabilities" => probs})
       when (is_map(probs) and not is_struct(probs) and map_size(probs) > 0) or
              (is_list(probs) and probs != []),
       do: true

  defp has_flat_score_probabilities?(_), do: false

  defp normalize_answers(raw_answers, %Prepared{} = prepared, source) do
    Enum.reduce_while(prepared.ordered_keys, {:ok, %{}}, fn caller_key, {:ok, acc} ->
      wire_key = to_string(caller_key)

      case normalize_one_answer(caller_key, raw_answers, prepared, source) do
        {:ok, ans} -> {:cont, {:ok, Map.put(acc, wire_key, ans)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp normalize_one_answer(caller_key, raw_answers, %Prepared{} = prepared, source) do
    wire_key = to_string(caller_key)
    defn = Map.fetch!(prepared.definitions, wire_key)

    case Map.fetch(raw_answers, wire_key) do
      {:ok, raw_ans} when is_map(raw_ans) and not is_struct(raw_ans) ->
        normalize_question_answer(caller_key, defn, raw_ans, source)

      _ ->
        invalid_response_error(
          ["answers", wire_key],
          "missing answer for question #{inspect(caller_key)}",
          :missing_answer,
          %{question: caller_key, answers: raw_answers},
          raw_answers
        )
    end
  end

  defp normalize_question_answer(caller_key, %{type: "noul"}, raw_ans, _source) do
    if invalid_noul_shape?(raw_ans) do
      invalid_answer_error(
        "invalid noul answer shape for #{inspect(caller_key)}",
        raw_ans,
        :invalid_noul_shape,
        caller_key
      )
    else
      case resolve_noul_probability(raw_ans) do
        {:ok, prob} ->
          {:ok, %NoulAnswer{noul: prob, id: caller_key, raw: raw_ans}}

        {:error, reason} ->
          invalid_answer_error(
            "invalid noul probability for #{inspect(caller_key)}: #{reason}",
            raw_ans,
            reason,
            caller_key
          )
      end
    end
  end

  defp normalize_question_answer(caller_key, %{type: "choice"} = defn, raw_ans, _source) do
    option_order = Map.get(defn, :option_order, [])
    valid_options = choice_valid_options(defn, option_order)

    with :ok <- validate_choice_shape(caller_key, raw_ans),
         {:ok, choice_str} <- extract_valid_choice(caller_key, raw_ans, valid_options),
         {:ok, parsed_probs} <-
           normalize_choice_probabilities(
             caller_key,
             raw_ans["probabilities"],
             valid_options,
             raw_ans
           ),
         {:ok, conf} <-
           resolve_choice_confidence(
             caller_key,
             raw_ans["confidence"],
             parsed_probs,
             choice_str,
             raw_ans
           ) do
      probs =
        if map_size(parsed_probs) == 0,
          do: backfill_choice_probabilities(choice_str, conf, valid_options),
          else: parsed_probs

      {:ok,
       %ChoiceAnswer{
         choice: choice_str,
         confidence: conf,
         probabilities: probs,
         id: caller_key,
         raw: raw_ans,
         option_order: option_order
       }}
    end
  end

  defp normalize_question_answer(caller_key, %{type: "score"} = defn, raw_ans, source) do
    levels = Map.get(defn, :levels, [])
    legend = Map.new(levels, fn lvl -> {lvl.index, lvl.label} end)
    max_index = max(length(levels) - 1, 0)

    with :ok <- validate_score_shape(caller_key, raw_ans),
         {:ok, parsed_probs} <-
           normalize_score_probabilities(caller_key, raw_ans["probabilities"], levels, raw_ans),
         {:ok, conf} <-
           resolve_score_confidence(caller_key, raw_ans["confidence"], parsed_probs, raw_ans),
         {:ok, score} <-
           normalize_score_value(caller_key, raw_ans, parsed_probs, max_index, source) do
      probs =
        if map_size(parsed_probs) == 0 and levels != [],
          do: backfill_score_probabilities(score, levels, max_index),
          else: parsed_probs

      {:ok,
       %ScoreAnswer{
         score: score,
         confidence: conf,
         legend: legend,
         probabilities: probs,
         id: caller_key,
         raw: raw_ans,
         levels: levels
       }}
    end
  end

  defp invalid_response_error(path, message, reason, extra_details, body) do
    %Error{} = err = Error.invalid_response(path, message, body)
    {:error, %Error{err | details: Map.put(extra_details, :reason, reason)}}
  end

  defp invalid_answer_error(message, raw_ans, reason, caller_key) do
    invalid_response_error(
      ["answers", to_string(caller_key)],
      message,
      reason,
      %{question: caller_key, answer: raw_ans},
      raw_ans
    )
  end

  defp invalid_noul_shape?(raw_ans) do
    Map.has_key?(raw_ans, "choice") or
      Map.has_key?(raw_ans, "score") or
      raw_ans["type"] not in [nil, "noul", "predicate"]
  end

  defp validate_choice_shape(caller_key, raw_ans) do
    if not Map.has_key?(raw_ans, "noul") and
         not Map.has_key?(raw_ans, "score") and
         raw_ans["type"] in [nil, "choice"] do
      :ok
    else
      invalid_answer_error(
        "invalid choice shape for #{inspect(caller_key)}",
        raw_ans,
        :invalid_choice_shape,
        caller_key
      )
    end
  end

  defp extract_valid_choice(caller_key, raw_ans, valid_options) do
    choice_raw = raw_ans["choice"]

    cond do
      not valid_choice_value?(choice_raw) ->
        invalid_answer_error(
          "invalid choice value for #{inspect(caller_key)}",
          raw_ans,
          :invalid_choice_value,
          caller_key
        )

      MapSet.size(valid_options) > 0 and
          not MapSet.member?(valid_options, to_string(choice_raw)) ->
        invalid_answer_error(
          "unknown choice #{inspect(choice_raw)} for #{inspect(caller_key)}",
          raw_ans,
          :unknown_choice,
          caller_key
        )

      true ->
        {:ok, to_string(choice_raw)}
    end
  end

  defp normalize_choice_probabilities(caller_key, raw_probs, valid_options, raw_ans) do
    with {:ok, probs} <- normalize_probabilities(raw_probs),
         true <- valid_choice_probability_keys?(probs, valid_options) do
      {:ok, probs}
    else
      _ ->
        invalid_answer_error(
          "invalid choice probabilities for #{inspect(caller_key)}",
          raw_ans,
          :invalid_probabilities,
          caller_key
        )
    end
  end

  defp valid_choice_probability_keys?(probs, valid_options) do
    MapSet.size(valid_options) == 0 or
      Enum.all?(Map.keys(probs), &MapSet.member?(valid_options, &1))
  end

  defp resolve_choice_confidence(caller_key, raw_conf, parsed_probs, choice_str, raw_ans) do
    conf =
      cond do
        not is_nil(raw_conf) -> raw_conf
        Map.has_key?(parsed_probs, choice_str) -> Map.fetch!(parsed_probs, choice_str)
        true -> 0.0
      end

    case clamp_unit_probability(conf) do
      {:ok, valid_conf} ->
        {:ok, valid_conf}

      :error ->
        invalid_answer_error(
          "invalid choice confidence for #{inspect(caller_key)}",
          raw_ans,
          :invalid_confidence,
          caller_key
        )
    end
  end

  defp validate_score_shape(caller_key, raw_ans) do
    if not Map.has_key?(raw_ans, "noul") and
         not Map.has_key?(raw_ans, "choice") and
         raw_ans["type"] in [nil, "score"] do
      :ok
    else
      invalid_answer_error(
        "invalid score shape for #{inspect(caller_key)}",
        raw_ans,
        :invalid_score_shape,
        caller_key
      )
    end
  end

  defp resolve_score_confidence(caller_key, raw_conf, parsed_probs, raw_ans) do
    conf =
      cond do
        not is_nil(raw_conf) -> raw_conf
        map_size(parsed_probs) > 0 -> parsed_probs |> Enum.max_by(&elem(&1, 1)) |> elem(1)
        true -> 0.0
      end

    case clamp_unit_probability(conf) do
      {:ok, valid_conf} ->
        {:ok, valid_conf}

      :error ->
        invalid_answer_error(
          "invalid score confidence for #{inspect(caller_key)}",
          raw_ans,
          :invalid_confidence,
          caller_key
        )
    end
  end

  defp resolve_noul_probability(raw_ans) do
    case find_boolean_field(raw_ans, @noul_boolean_keys) do
      {:ok, bool_val} ->
        resolve_boolean_noul(bool_val, raw_ans)

      :none ->
        resolve_first_numeric_noul(raw_ans)
    end
  end

  defp resolve_boolean_noul(bool_val, raw_ans) do
    case find_numeric_field(raw_ans, @noul_polarity_keys) do
      {:ok, prob_val} ->
        resolve_consistent_probability(bool_val, prob_val)

      :none ->
        case raw_ans["confidence"] do
          nil -> {:error, :missing_noul_confidence}
          conf -> resolve_boolean_confidence(bool_val, conf)
        end
    end
  end

  defp resolve_consistent_probability(bool_val, prob_val) do
    case clamp_unit_probability(prob_val) do
      {:ok, prob} ->
        if (bool_val and prob >= 0.5) or (not bool_val and prob <= 0.5) do
          {:ok, prob}
        else
          {:error, :contradictory_noul_polarity}
        end

      :error ->
        {:error, :invalid_noul_probability}
    end
  end

  defp find_boolean_field(raw_ans, keys) do
    Enum.find_value(keys, :none, fn key ->
      case Map.fetch(raw_ans, key) do
        {:ok, val} when is_boolean(val) -> {:ok, val}
        _ -> nil
      end
    end)
  end

  defp find_numeric_field(raw_ans, keys) do
    Enum.find_value(keys, :none, fn key ->
      case Map.fetch(raw_ans, key) do
        {:ok, val} when is_number(val) -> {:ok, val}
        _ -> nil
      end
    end)
  end

  defp resolve_first_numeric_noul(raw_ans) do
    case Enum.find(@noul_numeric_keys, &present_value?(raw_ans, &1)) do
      nil -> {:error, :missing_noul_probability}
      key -> resolve_numeric_prob(raw_ans[key])
    end
  end

  defp present_value?(map, key), do: Map.has_key?(map, key) and not is_nil(map[key])

  defp resolve_numeric_prob(val) do
    case clamp_unit_probability(val) do
      {:ok, prob} -> {:ok, prob}
      :error -> {:error, :invalid_noul_probability}
    end
  end

  defp resolve_boolean_confidence(bool, conf) do
    case clamp_unit_probability(conf) do
      {:ok, valid_conf} ->
        if valid_conf >= 0.5 do
          {:ok, if(bool, do: valid_conf, else: max(1.0 - valid_conf, 0.0))}
        else
          {:error, :contradictory_noul_polarity}
        end

      :error ->
        {:error, :invalid_noul_confidence}
    end
  end

  defp clamp_unit_probability(val) when is_number(val) do
    cond do
      val >= 0.0 and val <= 1.0 -> {:ok, val}
      val >= -@prob_epsilon and val < 0.0 -> {:ok, 0.0}
      val > 1.0 and val <= 1.0 + @prob_epsilon -> {:ok, 1.0}
      true -> :error
    end
  end

  defp clamp_unit_probability(_), do: :error

  defp backfill_choice_probabilities(choice_str, conf, valid_options)
       when is_number(conf) and conf >= 0.0 and conf <= 1.0 do
    n = MapSet.size(valid_options)

    cond do
      n == 0 ->
        %{choice_str => conf}

      n == 1 ->
        %{choice_str => 1.0}

      conf < 1.0 / n ->
        uniform = 1.0 / n
        Map.new(valid_options, &{&1, uniform})

      true ->
        others = valid_options |> MapSet.delete(choice_str) |> MapSet.to_list()
        remainder = max(1.0 - conf, 0.0) / length(others)

        others
        |> Map.new(&{&1, remainder})
        |> Map.put(choice_str, conf)
    end
  end

  defp backfill_choice_probabilities(choice_str, conf, _valid_options) do
    %{choice_str => conf}
  end

  defp backfill_score_probabilities(score, levels, max_index) do
    lo = trunc(Float.floor(score * 1.0))
    hi = min(lo + 1, max_index)
    hi_weight = max(min(score - lo, 1.0), 0.0)
    lo_weight = max(1.0 - hi_weight, 0.0)

    Map.new(levels, fn lvl ->
      weight =
        cond do
          lo == hi and lvl.index == lo -> 1.0
          lvl.index == lo -> lo_weight
          lvl.index == hi -> hi_weight
          true -> 0.0
        end

      {lvl.index, weight}
    end)
  end

  defp choice_valid_options(defn, option_order) do
    keys =
      cond do
        is_list(option_order) and option_order != [] ->
          Enum.map(option_order, &to_string/1)

        is_map(defn[:option_keys]) and map_size(defn[:option_keys]) > 0 ->
          defn[:option_keys] |> Map.keys() |> Enum.map(&to_string/1)

        is_list(defn[:criteria]) or (is_map(defn[:criteria]) and map_size(defn[:criteria]) > 0) ->
          Enum.map(defn[:criteria], fn {k, _v} -> to_string(k) end)

        true ->
          []
      end

    MapSet.new(keys)
  end

  defp valid_choice_value?(val) when is_binary(val), do: val != ""
  defp valid_choice_value?(val) when is_atom(val), do: not is_nil(val) and not is_boolean(val)
  defp valid_choice_value?(_), do: false

  defp normalize_score_value(caller_key, raw_ans, probs, max_index, source) do
    cond do
      Map.has_key?(raw_ans, "score") ->
        validate_and_clamp_score(caller_key, raw_ans["score"], probs, max_index, raw_ans)

      map_size(probs) > 0 ->
        expected_score_from_probs(caller_key, probs, max_index, raw_ans)

      score_proto3_zero_omission?(raw_ans, source) ->
        validate_and_clamp_score(caller_key, 0.0, probs, max_index, raw_ans)

      true ->
        invalid_answer_error(
          "invalid score value for #{inspect(caller_key)}",
          raw_ans,
          :invalid_score,
          caller_key
        )
    end
  end

  defp expected_score_from_probs(caller_key, probs, max_index, raw_ans) do
    prob_sum = Enum.reduce(probs, 0.0, fn {_idx, p}, acc -> acc + p end)

    expected =
      if prob_sum > 0.0 do
        Enum.reduce(probs, 0.0, fn {idx, p}, acc -> acc + idx * p end) / prob_sum
      else
        0.0
      end

    case clamp_score_range(expected, max_index) do
      {:ok, valid_score} ->
        {:ok, valid_score}

      :error ->
        invalid_answer_error(
          "score out of range for #{inspect(caller_key)}",
          raw_ans,
          :score_out_of_range,
          caller_key
        )
    end
  end

  defp score_proto3_zero_omission?(raw_ans, source) do
    raw_ans["type"] == "score" or
      Map.has_key?(raw_ans, "confidence") or
      Map.has_key?(raw_ans, "probabilities") or
      (source == :answers and raw_ans == %{})
  end

  defp validate_and_clamp_score(caller_key, raw_score, _probs, _max_index, raw_ans)
       when not is_number(raw_score) do
    invalid_answer_error(
      "invalid score value for #{inspect(caller_key)}",
      raw_ans,
      :invalid_score,
      caller_key
    )
  end

  defp validate_and_clamp_score(caller_key, raw_score, probs, max_index, raw_ans) do
    score = maybe_rescale_score(raw_score, probs, max_index)

    case clamp_score_range(score, max_index) do
      {:ok, valid_score} ->
        {:ok, valid_score}

      :error ->
        invalid_answer_error(
          "score out of range for #{inspect(caller_key)}",
          raw_ans,
          :score_out_of_range,
          caller_key
        )
    end
  end

  defp maybe_rescale_score(raw_score, probs, max_index)
       when max_index > 1 and map_size(probs) > 0 and raw_score >= -@prob_epsilon and
              raw_score <= 1.0 + @prob_epsilon do
    prob_sum = Enum.reduce(probs, 0.0, fn {_idx, p}, acc -> acc + p end)

    if prob_sum > 0.0 do
      unit_score = min(max(raw_score, 0.0), 1.0)
      expected = Enum.reduce(probs, 0.0, fn {idx, p}, acc -> acc + idx * p end) / prob_sum
      scaled = unit_score * max_index
      scaled_err = abs(scaled - expected)
      raw_err = abs(unit_score - expected)

      if scaled_err < 0.05 and scaled_err < raw_err do
        scaled
      else
        raw_score
      end
    else
      raw_score
    end
  end

  defp maybe_rescale_score(raw_score, _probs, _max_index), do: raw_score

  defp clamp_score_range(score, max_index) do
    cond do
      score >= 0.0 and score <= max_index -> {:ok, score}
      score >= -@prob_epsilon and score < 0.0 -> {:ok, 0.0}
      score > max_index and score <= max_index + @prob_epsilon -> {:ok, max_index * 1.0}
      true -> :error
    end
  end

  defp normalize_probabilities(nil), do: {:ok, %{}}

  defp normalize_probabilities(probs)
       when (is_map(probs) and not is_struct(probs)) or is_list(probs) do
    with {:ok, pairs} <- extract_probability_pairs(probs) do
      Enum.reduce_while(pairs, {:ok, %{}}, &put_clamped_probability/2)
    end
  end

  defp normalize_probabilities(_), do: :error

  defp put_clamped_probability({k, v}, {:ok, acc})
       when is_binary(k) or (is_atom(k) and not is_nil(k)) or is_integer(k) do
    key = to_string(k)

    with false <- Map.has_key?(acc, key),
         {:ok, prob} <- clamp_unit_probability(v) do
      {:cont, {:ok, Map.put(acc, key, prob)}}
    else
      _ -> {:halt, :error}
    end
  end

  defp put_clamped_probability(_pair, _acc), do: {:halt, :error}

  defp normalize_score_probabilities(_caller_key, nil, _levels, _raw_ans), do: {:ok, %{}}
  defp normalize_score_probabilities(_caller_key, [], _levels, _raw_ans), do: {:ok, %{}}

  defp normalize_score_probabilities(caller_key, raw_probs, levels, raw_ans)
       when (is_map(raw_probs) and not is_struct(raw_probs)) or is_list(raw_probs) do
    score_maps = build_score_maps(levels)

    case parse_score_probabilities(raw_probs, levels, score_maps) do
      {:ok, probs} ->
        {:ok, probs}

      :error ->
        invalid_answer_error(
          "invalid score probabilities for #{inspect(caller_key)}",
          raw_ans,
          :invalid_probabilities,
          caller_key
        )
    end
  end

  defp normalize_score_probabilities(caller_key, _raw_probs, _levels, raw_ans) do
    invalid_answer_error(
      "invalid score probabilities for #{inspect(caller_key)}",
      raw_ans,
      :invalid_probabilities,
      caller_key
    )
  end

  defp build_score_maps(levels) do
    label_to_idx = Map.new(levels, fn lvl -> {lvl.label, lvl.index} end)

    desc_to_idx =
      levels
      |> Enum.group_by(& &1.description)
      |> Enum.flat_map(fn
        {desc, [lvl]} when is_binary(desc) -> [{desc, lvl.index}]
        _ -> []
      end)
      |> Map.new()

    idx_set = MapSet.new(levels, & &1.index)
    {label_to_idx, desc_to_idx, idx_set}
  end

  defp parse_score_probabilities(raw_probs, levels, score_maps) when is_list(raw_probs) do
    if Enum.all?(raw_probs, &is_number/1) do
      parse_positional_score_probabilities(raw_probs, levels)
    else
      {label_to_idx, desc_to_idx, idx_set} = score_maps
      parse_score_prob_list_items(raw_probs, label_to_idx, desc_to_idx, idx_set)
    end
  end

  defp parse_score_probabilities(raw_probs, _levels, {label_to_idx, desc_to_idx, idx_set})
       when is_map(raw_probs) do
    pairs = Map.to_list(raw_probs)

    case reduce_label_or_desc_probabilities(pairs, label_to_idx, desc_to_idx) do
      {:ok, probs} ->
        {:ok, probs}

      :error ->
        if all_integer_indices?(pairs, idx_set) do
          reduce_integer_index_probabilities(pairs, idx_set)
        else
          :error
        end
    end
  end

  defp parse_positional_score_probabilities(raw_probs, levels) do
    if length(raw_probs) == length(levels) do
      raw_probs
      |> Enum.zip(levels)
      |> Enum.reduce_while({:ok, %{}}, &put_positional_prob/2)
    else
      :error
    end
  end

  defp put_positional_prob({val, lvl}, {:ok, acc}) do
    case clamp_unit_probability(val) do
      {:ok, prob} -> {:cont, {:ok, Map.put(acc, lvl.index, prob)}}
      :error -> {:halt, :error}
    end
  end

  defp parse_score_prob_list_items(items, label_to_idx, desc_to_idx, idx_set) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, acc} ->
      with {:ok, idx, raw_prob} <-
             resolve_score_list_item(item, label_to_idx, desc_to_idx, idx_set),
           false <- Map.has_key?(acc, idx),
           {:ok, prob} <- clamp_unit_probability(raw_prob) do
        {:cont, {:ok, Map.put(acc, idx, prob)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp resolve_score_list_item(
         %{"probability" => v} = item,
         label_to_idx,
         desc_to_idx,
         idx_set
       ) do
    candidates =
      [
        Map.get(item, "label"),
        Map.get(item, "description"),
        Map.get(item, "value")
      ]
      |> Enum.reject(&is_nil/1)

    resolved =
      Enum.find_value(
        candidates,
        &resolve_candidate_index(&1, label_to_idx, desc_to_idx, idx_set)
      ) || resolve_exact_index_candidate(Map.get(item, "index"), idx_set)

    case resolved do
      {:ok, idx} -> {:ok, idx, v}
      nil -> :error
    end
  end

  defp resolve_score_list_item(_, _, _, _), do: :error

  defp resolve_candidate_index(cand, label_to_idx, desc_to_idx, idx_set) do
    case resolve_score_index(cand, label_to_idx, desc_to_idx, idx_set) do
      {:ok, idx} -> {:ok, idx}
      :error -> nil
    end
  end

  defp resolve_exact_index_candidate(nil, _idx_set), do: nil

  defp resolve_exact_index_candidate(cand, idx_set) do
    case parse_exact_index(cand, idx_set) do
      {:ok, idx} -> {:ok, idx}
      :error -> nil
    end
  end

  defp all_integer_indices?(pairs, idx_set) do
    pairs
    |> Enum.reduce_while(MapSet.new(), &track_seen_index(&1, &2, idx_set))
    |> is_struct(MapSet)
  end

  defp track_seen_index({k, _v}, seen, idx_set) do
    with {:ok, idx} <- parse_exact_index(k, idx_set),
         false <- MapSet.member?(seen, idx) do
      {:cont, MapSet.put(seen, idx)}
    else
      _ -> {:halt, false}
    end
  end

  defp reduce_integer_index_probabilities(pairs, idx_set) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      with {:ok, idx} <- parse_exact_index(k, idx_set),
           {:ok, prob} <- clamp_unit_probability(v) do
        {:cont, {:ok, Map.put(acc, idx, prob)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp reduce_label_or_desc_probabilities(pairs, label_to_idx, desc_to_idx) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      with {:ok, idx} <- resolve_label_or_desc_index(k, label_to_idx, desc_to_idx),
           false <- Map.has_key?(acc, idx),
           {:ok, prob} <- clamp_unit_probability(v) do
        {:cont, {:ok, Map.put(acc, idx, prob)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp resolve_label_or_desc_index(k, label_to_idx, desc_to_idx)
       when is_binary(k) or (is_atom(k) and not is_nil(k)) do
    str = to_string(k)

    case Map.fetch(label_to_idx, str) do
      {:ok, idx} -> {:ok, idx}
      :error -> Map.fetch(desc_to_idx, str)
    end
  end

  defp resolve_label_or_desc_index(_, _, _), do: :error

  defp extract_probability_pairs(probs) when is_map(probs), do: {:ok, Map.to_list(probs)}

  defp extract_probability_pairs(probs) when is_list(probs) do
    probs
    |> Enum.reduce_while({:ok, []}, fn
      %{"value" => k, "probability" => v}, {:ok, acc} when not is_nil(k) ->
        {:cont, {:ok, [{k, v} | acc]}}

      %{"label" => k, "probability" => v}, {:ok, acc} when not is_nil(k) ->
        {:cont, {:ok, [{k, v} | acc]}}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, rev} -> {:ok, Enum.reverse(rev)}
      :error -> :error
    end
  end

  defp resolve_score_index(k, _label_to_idx, _desc_to_idx, idx_set) when is_integer(k) do
    if MapSet.member?(idx_set, k), do: {:ok, k}, else: :error
  end

  defp resolve_score_index(k, label_to_idx, desc_to_idx, idx_set)
       when is_binary(k) or is_atom(k) do
    str = to_string(k)

    with :error <- Map.fetch(label_to_idx, str),
         :error <- Map.fetch(desc_to_idx, str) do
      parse_score_index(str, idx_set)
    end
  end

  defp resolve_score_index(_, _, _, _), do: :error

  defp parse_exact_index(k, idx_set) when is_integer(k) do
    if MapSet.member?(idx_set, k), do: {:ok, k}, else: :error
  end

  defp parse_exact_index(k, idx_set) when is_binary(k) or is_atom(k) do
    parse_score_index(to_string(k), idx_set)
  end

  defp parse_exact_index(_, _), do: :error

  defp parse_score_index(str, idx_set) do
    case Integer.parse(str) do
      {int, ""} -> if MapSet.member?(idx_set, int), do: {:ok, int}, else: :error
      _ -> :error
    end
  end
end
