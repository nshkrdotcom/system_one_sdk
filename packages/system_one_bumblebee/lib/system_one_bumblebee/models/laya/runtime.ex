defmodule SystemOneBumblebee.Models.Laya.Runtime do
  @moduledoc """
  Resident native Laya runtime.

  The runtime loads the reviewed ModernBERT encoder, custom decision head,
  tokenizer and calibration config exactly once. Inference batches all
  questions in one System One request through that resident model state.
  """

  alias SystemOneBumblebee.{
    Artifacts,
    ModelManifest,
    RuntimeProfile
  }

  alias SystemOneBumblebee.Models.Laya.{
    Config,
    DecisionHead,
    DecisionHeadLoader,
    Decoder,
    EncoderLoader,
    Preprocessing,
    Tokenization
  }

  alias SystemOneContracts.V1.{
    Request,
    Response,
    Usage
  }

  @required_artifacts [
    "model.safetensors",
    "rl_agent_config.json",
    "encoder/config.json",
    "tokenizer/tokenizer.json"
  ]

  @enforce_keys [
    :model_name,
    :profile,
    :config,
    :tokenizer,
    :encoder_params,
    :head_params,
    :predict_fun,
    :head_forward_fun,
    :calibrate_fun,
    :action_softmax_fun
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          model_name: String.t(),
          profile: RuntimeProfile.t(),
          config: Config.t(),
          tokenizer: Tokenization.t(),
          encoder_params: term(),
          head_params: map(),
          predict_fun: function(),
          head_forward_fun: function(),
          calibrate_fun: function(),
          action_softmax_fun: function()
        }

  @spec load(
          ModelManifest.t(),
          Artifacts.Prepared.t(),
          RuntimeProfile.t(),
          keyword()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def load(
        %ModelManifest{} = manifest,
        %Artifacts.Prepared{} = artifacts,
        %RuntimeProfile{} = profile,
        opts \\ []
      )
      when is_list(opts) do
    with {:ok, parameter_type} <-
           parameter_type(profile),
         {:ok, paths} <-
           artifact_paths(artifacts),
         {:ok, config} <-
           Config.load(paths.config),
         :ok <-
           validate_profile_sequence_length(
             profile,
             config
           ),
         {:ok, tokenizer} <-
           Tokenization.load_file(paths.tokenizer),
         {:ok, encoder} <-
           EncoderLoader.load(
             paths.encoder_dir,
             paths.checkpoint,
             type: parameter_type,
             backend: backend(profile),
             log_params_diff:
               Keyword.get(
                 opts,
                 :log_params_diff,
                 false
               )
           ),
         {:ok, head} <-
           DecisionHeadLoader.load(
             paths.checkpoint,
             backend: backend(profile),
             type: parameter_type
           ),
         {:ok, predict_fun} <-
           predictor(
             encoder.model,
             profile
           ) do
      {:ok,
       %__MODULE__{
         model_name: manifest.name,
         profile: profile,
         config: config,
         tokenizer: tokenizer,
         encoder_params: encoder.params,
         head_params: head.params,
         predict_fun: predict_fun,
         head_forward_fun:
           compile(
             &DecisionHead.forward/6,
             profile
           ),
         calibrate_fun:
           compile(
             &DecisionHead.calibrated_probabilities/2,
             profile
           ),
         action_softmax_fun:
           compile(
             &DecisionHead.action_probabilities/1,
             profile
           )
       }}
    end
  rescue
    error ->
      {:error, {:laya_runtime_load_failed, Exception.message(error)}}
  end

  @spec infer(
          t(),
          Request.t(),
          keyword()
        ) ::
          {:ok, Response.t()}
          | {:error, term()}
  def infer(
        %__MODULE__{} = runtime,
        %Request{} = request,
        _opts \\ []
      ) do
    with {:ok, batch} <-
           build_batch(
             runtime,
             request
           ),
         {:ok, outputs} <-
           execute(
             runtime,
             batch
           ),
         {:ok, answers} <-
           decode_answers(
             batch,
             outputs
           ) do
      {:ok,
       %Response{
         model: runtime.model_name,
         usage: %Usage{
           input_tokens: batch.input_tokens,
           output_tokens: 0
         },
         answers: answers,
         metadata: %{
           "adapter" => "laya",
           "runtime_profile" => to_string(runtime.profile.name)
         }
       }}
    end
  rescue
    error ->
      {:error, {:laya_inference_failed, Exception.message(error)}}
  end

  defp build_batch(
         %__MODULE__{} = runtime,
         %Request{} = request
       ) do
    request.questions
    |> Enum.reduce_while(
      {:ok, []},
      fn {key, question}, {:ok, acc} ->
        case build_item(
               runtime,
               key,
               request.state,
               question
             ) do
          {:ok, item} ->
            {:cont, {:ok, [item | acc]}}

          {:error, _} = error ->
            {:halt, error}
        end
      end
    )
    |> case do
      {:ok, reversed} ->
        finalize_batch(
          runtime,
          Enum.reverse(reversed)
        )

      {:error, _} = error ->
        error
    end
  end

  defp build_item(
         runtime,
         key,
         state,
         question
       ) do
    with {:ok, normalized} <-
           Preprocessing.normalize_question(question),
         {:ok, sequence} <-
           Tokenization.build_sequence(
             runtime.tokenizer,
             state,
             normalized,
             max_len: runtime.config.max_len,
             head_max_len: runtime.config.head_max_len
           ),
         :ok <-
           validate_sequence_option_count(
             normalized,
             sequence
           ),
         {:ok, temperature} <-
           Config.temperature_for(
             runtime.config,
             normalized.type,
             length(sequence.marker_positions)
           ) do
      {:ok,
       %{
         key: key,
         question: normalized,
         sequence: sequence,
         temperature: temperature
       }}
    end
  end

  defp finalize_batch(
         _runtime,
         []
       ),
       do: {:error, :empty_laya_request}

  defp finalize_batch(
         runtime,
         items
       ) do
    max_sequence_length =
      items
      |> Enum.map(&length(&1.sequence.input_ids))
      |> Enum.max()

    max_marker_count =
      items
      |> Enum.map(&length(&1.sequence.marker_positions))
      |> Enum.max()

    with {:ok, sequence_length} <-
           batch_sequence_length(
             runtime,
             max_sequence_length
           ) do
      pad_id =
        runtime.tokenizer.special_ids.pad

      {:ok,
       %{
         items: items,
         sequence_length: sequence_length,
         marker_count: max_marker_count,
         input_ids:
           Enum.map(
             items,
             &pad_right(
               &1.sequence.input_ids,
               sequence_length,
               pad_id
             )
           ),
         attention_mask:
           Enum.map(
             items,
             &pad_right(
               &1.sequence.attention_mask,
               sequence_length,
               0
             )
           ),
         marker_positions:
           Enum.map(
             items,
             &pad_right(
               &1.sequence.marker_positions,
               max_marker_count,
               0
             )
           ),
         marker_mask:
           Enum.map(
             items,
             fn item ->
               item.sequence.marker_mask
               |> pad_right(
                 max_marker_count,
                 false
               )
               |> Enum.map(fn
                 true -> 1
                 false -> 0
               end)
             end
           ),
         qtypes:
           Enum.map(
             items,
             & &1.sequence.qtype
           ),
         temperatures:
           Enum.map(
             items,
             &[&1.temperature]
           ),
         input_tokens:
           Enum.reduce(
             items,
             0,
             fn item, acc ->
               acc +
                 Enum.sum(item.sequence.attention_mask)
             end
           )
       }}
    end
  end

  defp execute(
         runtime,
         batch
       ) do
    input = %{
      "input_ids" =>
        tensor(
          batch.input_ids,
          :u32,
          runtime.profile
        ),
      "attention_mask" =>
        tensor(
          batch.attention_mask,
          :u32,
          runtime.profile
        )
    }

    encoder_outputs =
      runtime.predict_fun.(
        runtime.encoder_params,
        input
      )

    hidden =
      hidden_state!(encoder_outputs)

    head_attention_mask =
      tensor(
        batch.attention_mask,
        :u8,
        runtime.profile
      )

    head =
      runtime.head_forward_fun.(
        hidden,
        head_attention_mask,
        tensor(
          batch.marker_positions,
          :s32,
          runtime.profile
        ),
        tensor(
          batch.marker_mask,
          :u8,
          runtime.profile
        ),
        tensor(
          batch.qtypes,
          :s32,
          runtime.profile
        ),
        runtime.head_params
      )

    probabilities =
      runtime.calibrate_fun.(
        head.logits,
        tensor(
          batch.temperatures,
          :f32,
          runtime.profile
        )
      )

    action_probabilities =
      runtime.action_softmax_fun.(head.action_logits)

    {:ok,
     %{
       probabilities:
         rows(
           probabilities,
           batch.marker_count
         ),
       action_probabilities:
         rows(
           action_probabilities,
           2
         )
     }}
  end

  defp decode_answers(
         batch,
         outputs
       ) do
    batch.items
    |> Enum.zip(outputs.probabilities)
    |> Enum.zip(outputs.action_probabilities)
    |> Enum.reduce_while(
      {:ok, %{}},
      fn
        {{item, probability_row}, action_row}, {:ok, answers} ->
          option_count =
            length(item.sequence.marker_positions)

          probabilities =
            Enum.take(
              probability_row,
              option_count
            )

          action_probability =
            Enum.fetch!(
              action_row,
              0
            )

          case Decoder.decode(
                 item.question,
                 probabilities,
                 action_probability
               ) do
            {:ok, answer} ->
              {:cont,
               {:ok,
                Map.put(
                  answers,
                  item.key,
                  answer
                )}}

            {:error, reason} ->
              {:halt, {:error, {:laya_decode_failed, item.key, reason}}}
          end
      end
    )
  end

  defp artifact_paths(%Artifacts.Prepared{
         files: files
       }) do
    missing =
      Enum.reject(
        @required_artifacts,
        &Map.has_key?(
          files,
          &1
        )
      )

    if missing == [] do
      {:ok,
       %{
         checkpoint:
           Map.fetch!(
             files,
             "model.safetensors"
           ),
         config:
           Map.fetch!(
             files,
             "rl_agent_config.json"
           ),
         encoder_dir:
           files
           |> Map.fetch!("encoder/config.json")
           |> Path.dirname(),
         tokenizer:
           Map.fetch!(
             files,
             "tokenizer/tokenizer.json"
           )
       }}
    else
      {:error, {:missing_laya_artifacts, missing}}
    end
  end

  defp parameter_type(%RuntimeProfile{
         type: type
       })
       when type in [
              :f16,
              :bf16,
              :f32
            ],
       do: {:ok, type}

  defp parameter_type(%RuntimeProfile{
         type: type
       }),
       do: {:error, {:invalid_laya_runtime_type, type}}

  defp validate_profile_sequence_length(
         %RuntimeProfile{
           sequence_length: nil
         },
         _config
       ),
       do: :ok

  defp validate_profile_sequence_length(
         %RuntimeProfile{
           sequence_length: length
         },
         %Config{
           max_len: max_len
         }
       )
       when is_integer(length) and
              length <= max_len,
       do: :ok

  defp validate_profile_sequence_length(
         %RuntimeProfile{
           sequence_length: length
         },
         %Config{
           max_len: max_len
         }
       ),
       do: {:error, {:laya_sequence_length_exceeds_model_limit, length, max_len}}

  defp validate_sequence_option_count(
         %{
           type: "choice",
           criteria: criteria
         },
         sequence
       ),
       do:
         validate_sequence_option_count(
           length(criteria),
           sequence
         )

  defp validate_sequence_option_count(
         %{
           type: "score",
           criteria: criteria
         },
         sequence
       ),
       do:
         validate_sequence_option_count(
           length(criteria),
           sequence
         )

  defp validate_sequence_option_count(
         %{type: "noul"},
         sequence
       ),
       do:
         validate_sequence_option_count(
           2,
           sequence
         )

  defp validate_sequence_option_count(
         expected,
         sequence
       )
       when is_integer(expected) do
    actual =
      length(sequence.marker_positions)

    if actual == expected do
      :ok
    else
      {:error, {:laya_sequence_option_count_mismatch, expected, actual}}
    end
  end

  defp batch_sequence_length(
         %__MODULE__{
           profile: %RuntimeProfile{
             sequence_length: nil
           }
         },
         actual
       ),
       do: {:ok, actual}

  defp batch_sequence_length(
         %__MODULE__{
           profile: %RuntimeProfile{
             sequence_length: configured
           }
         },
         actual
       ) do
    if configured >= actual do
      {:ok, configured}
    else
      {:error, {:laya_request_exceeds_profile_sequence_length, actual, configured}}
    end
  end

  defp predictor(
         model,
         profile
       ) do
    {_init_fun, predict_fun} =
      Axon.build(
        model,
        mode: :inference
      )

    {:ok,
     compile(
       predict_fun,
       profile
     )}
  rescue
    error ->
      {:error, {:laya_predictor_build_failed, Exception.message(error)}}
  end

  defp compile(
         fun,
         %RuntimeProfile{
           compiler: nil
         }
       ),
       do: fun

  defp compile(
         fun,
         %RuntimeProfile{
           compiler: compiler,
           defn_options: options
         }
       ) do
    options =
      options
      |> Keyword.put_new(
        :on_conflict,
        :reuse
      )
      |> Keyword.put(
        :compiler,
        compiler
      )

    Nx.Defn.jit(
      fun,
      options
    )
  end

  defp backend(%RuntimeProfile{
         backend: nil
       }),
       do: Nx.BinaryBackend

  defp backend(%RuntimeProfile{
         backend: backend
       }),
       do: backend

  defp tensor(
         values,
         type,
         profile
       ) do
    Nx.tensor(
      values,
      type: type,
      backend: backend(profile)
    )
  end

  defp hidden_state!(outputs)
       when is_map(outputs) do
    cond do
      Map.has_key?(
        outputs,
        :hidden_state
      ) ->
        Map.fetch!(
          outputs,
          :hidden_state
        )

      Map.has_key?(
        outputs,
        "hidden_state"
      ) ->
        Map.fetch!(
          outputs,
          "hidden_state"
        )

      true ->
        raise("ModernBERT output missing hidden_state")
    end
  end

  defp rows(
         tensor,
         width
       ) do
    tensor
    |> Nx.backend_transfer(Nx.BinaryBackend)
    |> Nx.to_flat_list()
    |> Enum.chunk_every(width)
  end

  defp pad_right(
         values,
         target,
         pad
       ) do
    values ++
      List.duplicate(
        pad,
        target - length(values)
      )
  end
end
