defmodule SystemOneBumblebee.Models.Laya.Decoder do
  @moduledoc """
  Exact native decoding semantics for Laya System One answers.

  This module translates already-calibrated option probabilities and
  action probabilities into Laya-native Choice, Score and Noul answer maps.

  Calibration itself remains separate. The canonical System One adapter may
  subsequently project these native maps onto the smaller provider-neutral
  wire contract; in particular, Laya's action probability is model-specific
  metadata rather than a new canonical answer type.
  """

  alias SystemOneBumblebee.Models.Laya.Preprocessing

  @type answer :: map()

  @doc """
  Decodes a Laya question from calibrated option probabilities.

  `action_probability` is probability index zero from the softmax of Laya's
  two action logits.

  All externally reported numeric values follow upstream and are rounded to
  four decimal places.
  """
  @spec decode(map(), [number()], number()) ::
          {:ok, answer()}
          | {:error, term()}
  def decode(
        question,
        probabilities,
        action_probability
      )
      when is_map(question) and
             is_list(probabilities) and
             is_number(action_probability) do
    with {:ok, normalized} <-
           Preprocessing.normalize_question(question),
         {:ok, probabilities} <-
           normalize_probabilities(probabilities),
         {:ok, option_count} <-
           option_count(normalized),
         :ok <-
           validate_probability_count(
             probabilities,
             option_count
           ),
         :ok <-
           validate_action_probability(action_probability) do
      action = %{
        "act_probability" => round4(action_probability)
      }

      {:ok,
       decode_normalized(
         normalized,
         probabilities,
         action
       )}
    end
  end

  def decode(
        question,
        probabilities,
        action_probability
      ) do
    {:error,
     {:invalid_laya_decode_input,
      %{
        question: question,
        probabilities: probabilities,
        action_probability: action_probability
      }}}
  end

  @doc """
  Same as `decode/3`, raising when the supplied question or probabilities
  are invalid.
  """
  @spec decode!(map(), [number()], number()) :: answer()
  def decode!(
        question,
        probabilities,
        action_probability
      ) do
    case decode(
           question,
           probabilities,
           action_probability
         ) do
      {:ok, answer} ->
        answer

      {:error, reason} ->
        raise ArgumentError,
              "failed to decode Laya answer: " <>
                inspect(reason)
    end
  end

  @doc """
  Upstream normalized Shannon-entropy confidence:

      1 - H(p) / log(k)

  The result is clamped to `[0, 1]`. For a single option the confidence
  is `1.0`.
  """
  @spec confidence([number()]) :: float()
  def confidence(probabilities)
      when is_list(probabilities) do
    probabilities =
      Enum.map(
        probabilities,
        &to_float/1
      )

    case length(probabilities) do
      count when count < 2 ->
        1.0

      count ->
        entropy =
          Enum.reduce(
            probabilities,
            0.0,
            fn probability, acc ->
              clipped =
                probability
                |> max(1.0e-12)
                |> min(1.0)

              acc -
                probability *
                  :math.log(clipped)
            end
          )

        value =
          1.0 -
            entropy /
              :math.log(count * 1.0)

        value
        |> max(0.0)
        |> min(1.0)
    end
  end

  defp decode_normalized(
         %{
           type: "choice",
           criteria: criteria
         },
         probabilities,
         action
       ) do
    keys =
      Enum.map(
        criteria,
        fn {key, _criterion} ->
          to_string(key)
        end
      )

    selected_index =
      argmax_index(probabilities)

    probability_map =
      zip_probability_map(
        keys,
        probabilities
      )

    %{
      "type" => "choice",
      "choice" =>
        Enum.fetch!(
          keys,
          selected_index
        ),
      "probabilities" => probability_map,
      "confidence" =>
        probabilities
        |> confidence()
        |> round4(),
      "action" => action
    }
  end

  defp decode_normalized(
         %{
           type: "score",
           criteria: criteria
         },
         probabilities,
         action
       ) do
    indices =
      criteria
      |> Enum.with_index()
      |> Enum.map(fn {_criterion, index} ->
        Integer.to_string(index)
      end)

    legend =
      criteria
      |> Enum.with_index()
      |> Map.new(fn {criterion, index} ->
        {
          Integer.to_string(index),
          criterion
        }
      end)

    expected_score =
      probabilities
      |> Enum.with_index()
      |> Enum.reduce(
        0.0,
        fn {probability, index}, acc ->
          acc +
            probability *
              index
        end
      )

    %{
      "type" => "score",
      "score" => round4(expected_score),
      "legend" => legend,
      "probabilities" =>
        zip_probability_map(
          indices,
          probabilities
        ),
      "confidence" =>
        probabilities
        |> confidence()
        |> round4(),
      "action" => action
    }
  end

  defp decode_normalized(
         %{type: "noul"},
         probabilities,
         action
       ) do
    true_probability =
      Enum.fetch!(
        probabilities,
        1
      )

    %{
      "type" => "noul",
      "noul" => round4(true_probability),
      "confidence" =>
        true_probability
        |> max(
          1.0 -
            true_probability
        )
        |> round4(),
      "action" => action
    }
  end

  defp option_count(%{
         type: "choice",
         criteria: criteria
       })
       when is_list(criteria) do
    positive_count(
      "choice",
      length(criteria)
    )
  end

  defp option_count(%{
         type: "score",
         criteria: criteria
       })
       when is_list(criteria) do
    positive_count(
      "score",
      length(criteria)
    )
  end

  defp option_count(%{type: "noul"}),
    do: {:ok, 2}

  defp option_count(question),
    do: {:error, {:invalid_laya_decode_question, question}}

  defp positive_count(
         _type,
         count
       )
       when count > 0,
       do: {:ok, count}

  defp positive_count(
         type,
         count
       ),
       do: {:error, {:invalid_laya_option_count, type, count}}

  defp normalize_probabilities(probabilities) do
    probabilities
    |> Enum.reduce_while(
      {:ok, []},
      fn probability, {:ok, acc} ->
        if valid_probability?(probability) do
          {:cont,
           {:ok,
            [
              to_float(probability)
              | acc
            ]}}
        else
          {:halt, {:error, {:invalid_laya_probability, probability}}}
        end
      end
    )
    |> case do
      {:ok, normalized} ->
        {:ok, Enum.reverse(normalized)}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_probability_count(
         probabilities,
         expected
       ) do
    actual =
      length(probabilities)

    if actual == expected do
      :ok
    else
      {:error,
       {:laya_probability_count_mismatch,
        %{
          expected: expected,
          actual: actual
        }}}
    end
  end

  defp validate_action_probability(value) do
    if valid_probability?(value) do
      :ok
    else
      {:error, {:invalid_laya_action_probability, value}}
    end
  end

  defp valid_probability?(value)
       when is_number(value),
       do:
         value >= 0 and
           value <= 1

  defp valid_probability?(_value),
    do: false

  defp zip_probability_map(
         keys,
         probabilities
       ) do
    keys
    |> Enum.zip(probabilities)
    |> Map.new(fn {key, probability} ->
      {
        key,
        round4(probability)
      }
    end)
  end

  defp argmax_index([
         first
         | rest
       ]) do
    rest
    |> Enum.with_index(1)
    |> Enum.reduce(
      {first, 0},
      fn {probability, index}, {best_probability, best_index} ->
        if probability >
             best_probability do
          {probability, index}
        else
          {
            best_probability,
            best_index
          }
        end
      end
    )
    |> elem(1)
  end

  defp argmax_index([]),
    do:
      raise(
        ArgumentError,
        "cannot select an option from an empty probability list"
      )

  defp round4(value),
    do:
      value
      |> to_float()
      |> Float.round(4)

  defp to_float(value)
       when is_float(value),
       do: value

  defp to_float(value)
       when is_integer(value),
       do: value * 1.0
end
