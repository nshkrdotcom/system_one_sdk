defmodule SystemOneBumblebee.Models.Laya.DecisionHead do
  @moduledoc """
  Native Nx implementation of Laya's trained decision head.

  This module implements only model mathematics. It owns no artifact
  resolution, accelerator selection, serving process, or System One
  response translation.

  The parameter layout intentionally preserves the PyTorch checkpoint
  layout for the custom Laya head. In particular:

    * attention `in_proj_weight` remains packed as `[3 * d, d]`;
    * PyTorch linear matrices remain `[out_features, in_features]`;
    * Q/K/V are sliced at execution time rather than rewritten at load;
    * the two TransformerEncoder layers use pre-norm ordering;
    * the Transformer FFN activation is ReLU;
    * the scorer and action MLP activations are exact GELU.

  The encoder itself remains owned by Bumblebee's ModernBERT
  implementation.
  """

  import Nx.Defn

  @hidden_size 1_024
  @num_heads 16
  @head_size 64
  @ffn_size 4_096
  @action_hidden_size 256
  @layer_norm_epsilon 1.0e-5
  @attention_scale 8.0
  @attention_mask_value -1.0e30
  @marker_mask_value -1.0e4

  @typedoc "One checkpoint-to-runtime destination contract entry."
  @type contract_entry :: %{
          source: String.t(),
          destination: String.t(),
          family: atom(),
          shape: [non_neg_integer()],
          transform: atom()
        }

  @doc """
  Returns the actual runtime parameter contract for the trained custom
  head, excluding the checkpoint's `temperature` buffer.

  Unlike the Bumblebee encoder mapping, the custom head preserves the
  PyTorch matrix layout. No QKV splitting or matrix transposition occurs
  during loading.
  """
  @spec source_contract() :: [contract_entry()]
  def source_contract do
    [
      %{
        source: "type_emb.weight",
        destination: "type_embedding",
        family: :type_emb,
        shape: [3, @hidden_size],
        transform: :identity
      }
    ] ++
      Enum.flat_map(
        0..1,
        &layer_contract/1
      ) ++
      scorer_contract() ++
      action_contract()
  end

  @doc """
  Returns the custom-head contract including the checkpoint
  `temperature` buffer.

  The buffer is accounted for independently from the calibration
  configuration in `rl_agent_config.json`. Upstream inference selects
  its externally applied temperatures from that JSON configuration.
  """
  @spec checkpoint_contract() :: [contract_entry()]
  def checkpoint_contract do
    source_contract() ++
      [
        %{
          source: "temperature",
          destination: "checkpoint_temperature",
          family: :temperature,
          shape: [3],
          transform: :identity
        }
      ]
  end

  @doc """
  Executes the complete trained Laya custom head from ModernBERT hidden
  states through raw option logits and action logits.

  `marker_mask` is applied to option logits exactly as upstream:
  unavailable marker slots receive `-1.0e4`.

  Calibration is deliberately separate because option-count-specific
  temperatures belong to model configuration, not this trained graph.
  """
  defn forward(
         encoder_hidden,
         attention_mask,
         marker_pos,
         marker_mask,
         qtype,
         params
       ) do
    hidden =
      add_type_embedding(
        encoder_hidden,
        qtype,
        params.type_embedding
      )

    hidden =
      transformer_layer(
        hidden,
        attention_mask,
        params.layer0
      )

    hidden =
      transformer_layer(
        hidden,
        attention_mask,
        params.layer1
      )

    marker_hidden =
      gather_markers(
        hidden,
        marker_pos
      )

    scorer_norm =
      layer_norm(
        marker_hidden,
        params.scorer_norm_weight,
        params.scorer_norm_bias
      )

    scorer_linear =
      linear3(
        scorer_norm,
        params.scorer_linear_weight,
        params.scorer_linear_bias
      )

    scorer_gelu =
      Axon.Activations.gelu(scorer_linear)

    logits =
      scorer_gelu
      |> linear3(
        params.scorer_output_weight,
        params.scorer_output_bias
      )
      |> Nx.squeeze(axes: [2])
      |> Nx.as_type(:f32)
      |> mask_marker_logits(marker_mask)

    uncalibrated_probabilities =
      softmax2(logits)

    action_features =
      action_features(
        uncalibrated_probabilities,
        marker_mask
      )

    pooled =
      hidden
      |> Nx.slice_along_axis(
        0,
        1,
        axis: 1
      )
      |> Nx.squeeze(axes: [1])
      |> Nx.as_type(:f32)

    action_input =
      Nx.concatenate(
        [
          pooled,
          action_features
        ],
        axis: 1
      )

    action_hidden =
      action_input
      |> linear2(
        params.action_linear_weight,
        params.action_linear_bias
      )
      |> Axon.Activations.gelu()

    action_logits =
      action_hidden
      |> linear2(
        params.action_output_weight,
        params.action_output_bias
      )
      |> Nx.as_type(:f32)

    %{
      hidden_state: hidden,
      marker_hidden: marker_hidden,
      logits: logits,
      uncalibrated_probabilities: uncalibrated_probabilities,
      action_features: action_features,
      action_logits: action_logits
    }
  end

  @doc """
  Applies the selected external calibration temperature to raw option
  logits and returns probabilities.
  """
  defn calibrated_probabilities(
         logits,
         temperature
       ) do
    scale =
      Nx.max(
        temperature,
        1.0e-3
      )

    logits
    |> Nx.divide(scale)
    |> softmax2()
  end

  @doc """
  Converts the two action logits to upstream-compatible action
  probabilities.
  """
  defn action_probabilities(action_logits) do
    softmax2(action_logits)
  end

  defnp add_type_embedding(
          hidden,
          qtype,
          type_embedding
        ) do
    embedding =
      type_embedding
      |> Nx.take(qtype)
      |> Nx.new_axis(1)

    hidden + embedding
  end

  defnp transformer_layer(
          input,
          attention_mask,
          params
        ) do
    batch_size =
      Nx.axis_size(
        input,
        0
      )

    sequence_length =
      Nx.axis_size(
        input,
        1
      )

    norm1 =
      layer_norm(
        input,
        params.norm1_weight,
        params.norm1_bias
      )

    qkv =
      linear3(
        norm1,
        params.in_proj_weight,
        params.in_proj_bias
      )

    query =
      qkv
      |> Nx.slice_along_axis(
        0,
        @hidden_size,
        axis: 2
      )
      |> split_heads(
        batch_size,
        sequence_length
      )

    key =
      qkv
      |> Nx.slice_along_axis(
        @hidden_size,
        @hidden_size,
        axis: 2
      )
      |> split_heads(
        batch_size,
        sequence_length
      )

    value =
      qkv
      |> Nx.slice_along_axis(
        2 * @hidden_size,
        @hidden_size,
        axis: 2
      )
      |> split_heads(
        batch_size,
        sequence_length
      )

    scores =
      Nx.dot(
        query,
        [3],
        [0, 1],
        key,
        [3],
        [0, 1]
      ) / @attention_scale

    padding_mask =
      attention_mask
      |> Nx.equal(0)
      |> Nx.reshape({
        batch_size,
        1,
        1,
        sequence_length
      })
      |> Nx.broadcast({
        batch_size,
        @num_heads,
        sequence_length,
        sequence_length
      })

    scores =
      Nx.select(
        padding_mask,
        Nx.broadcast(
          @attention_mask_value,
          {
            batch_size,
            @num_heads,
            sequence_length,
            sequence_length
          }
        ),
        scores
      )

    probabilities =
      softmax4(scores)

    context =
      Nx.dot(
        probabilities,
        [3],
        [0, 1],
        value,
        [2],
        [0, 1]
      )

    merged =
      context
      |> Nx.transpose(axes: [0, 2, 1, 3])
      |> Nx.reshape({
        batch_size,
        sequence_length,
        @hidden_size
      })

    attention_output =
      linear3(
        merged,
        params.out_proj_weight,
        params.out_proj_bias
      )

    after_attention =
      input + attention_output

    norm2 =
      layer_norm(
        after_attention,
        params.norm2_weight,
        params.norm2_bias
      )

    feed_forward_hidden =
      norm2
      |> linear3(
        params.linear1_weight,
        params.linear1_bias
      )
      |> Nx.max(0.0)

    feed_forward_output =
      linear3(
        feed_forward_hidden,
        params.linear2_weight,
        params.linear2_bias
      )

    after_attention +
      feed_forward_output
  end

  defnp gather_markers(
          hidden,
          marker_pos
        ) do
    batch_size =
      Nx.axis_size(
        hidden,
        0
      )

    marker_count =
      Nx.axis_size(
        marker_pos,
        1
      )

    indices =
      marker_pos
      |> Nx.max(0)
      |> Nx.reshape({
        batch_size,
        marker_count,
        1
      })
      |> Nx.broadcast({
        batch_size,
        marker_count,
        @hidden_size
      })

    Nx.take_along_axis(
      hidden,
      indices,
      axis: 1
    )
  end

  defnp action_features(
          probabilities,
          marker_mask
        ) do
    batch_size =
      Nx.axis_size(
        probabilities,
        0
      )

    {top2, _indices} =
      Nx.top_k(
        probabilities,
        k: 2
      )

    top1 =
      Nx.slice_along_axis(
        top2,
        0,
        1,
        axis: 1
      )

    runner_up =
      Nx.slice_along_axis(
        top2,
        1,
        1,
        axis: 1
      )

    option_count =
      marker_mask
      |> Nx.as_type(:f32)
      |> Nx.sum(axes: [1])
      |> Nx.max(2.0)

    entropy =
      probabilities
      |> Nx.max(1.0e-9)
      |> Nx.log()
      |> Nx.multiply(probabilities)
      |> Nx.sum(axes: [1])
      |> Nx.negate()
      |> Nx.divide(Nx.log(option_count))
      |> Nx.reshape({batch_size, 1})

    count_feature =
      option_count
      |> Nx.divide(255.0)
      |> Nx.reshape({batch_size, 1})

    Nx.concatenate(
      [
        top1,
        top1 - runner_up,
        entropy,
        count_feature
      ],
      axis: 1
    )
  end

  defnp mask_marker_logits(
          logits,
          marker_mask
        ) do
    Nx.select(
      Nx.equal(
        marker_mask,
        0
      ),
      Nx.broadcast(
        @marker_mask_value,
        Nx.shape(logits)
      ),
      logits
    )
  end

  defnp split_heads(
          tensor,
          batch_size,
          sequence_length
        ) do
    tensor
    |> Nx.reshape({
      batch_size,
      sequence_length,
      @num_heads,
      @head_size
    })
    |> Nx.transpose(axes: [0, 2, 1, 3])
  end

  defnp linear3(
          input,
          weight,
          bias
        ) do
    Nx.dot(
      input,
      [2],
      [],
      weight,
      [1],
      []
    ) + bias
  end

  defnp linear2(
          input,
          weight,
          bias
        ) do
    Nx.dot(
      input,
      [1],
      [],
      weight,
      [1],
      []
    ) + bias
  end

  defnp layer_norm(
          input,
          weight,
          bias
        ) do
    mean =
      Nx.mean(
        input,
        axes: [2],
        keep_axes: true
      )

    centered =
      input - mean

    variance =
      centered
      |> Nx.multiply(centered)
      |> Nx.mean(
        axes: [2],
        keep_axes: true
      )

    normalized =
      centered /
        Nx.sqrt(
          variance +
            @layer_norm_epsilon
        )

    normalized * weight + bias
  end

  defnp softmax2(input) do
    maximum =
      Nx.reduce_max(
        input,
        axes: [1],
        keep_axes: true
      )

    exponentials =
      input
      |> Nx.subtract(maximum)
      |> Nx.exp()

    exponentials /
      Nx.sum(
        exponentials,
        axes: [1],
        keep_axes: true
      )
  end

  defnp softmax4(input) do
    maximum =
      Nx.reduce_max(
        input,
        axes: [3],
        keep_axes: true
      )

    exponentials =
      input
      |> Nx.subtract(maximum)
      |> Nx.exp()

    exponentials /
      Nx.sum(
        exponentials,
        axes: [3],
        keep_axes: true
      )
  end

  defp layer_contract(index) do
    prefix =
      "head.layers.#{index}"

    destination =
      "layer#{index}"

    [
      contract(
        "#{prefix}.self_attn.in_proj_weight",
        "#{destination}.in_proj_weight",
        :decision_head,
        [3 * @hidden_size, @hidden_size]
      ),
      contract(
        "#{prefix}.self_attn.in_proj_bias",
        "#{destination}.in_proj_bias",
        :decision_head,
        [3 * @hidden_size]
      ),
      contract(
        "#{prefix}.self_attn.out_proj.weight",
        "#{destination}.out_proj_weight",
        :decision_head,
        [@hidden_size, @hidden_size]
      ),
      contract(
        "#{prefix}.self_attn.out_proj.bias",
        "#{destination}.out_proj_bias",
        :decision_head,
        [@hidden_size]
      ),
      contract(
        "#{prefix}.linear1.weight",
        "#{destination}.linear1_weight",
        :decision_head,
        [@ffn_size, @hidden_size]
      ),
      contract(
        "#{prefix}.linear1.bias",
        "#{destination}.linear1_bias",
        :decision_head,
        [@ffn_size]
      ),
      contract(
        "#{prefix}.linear2.weight",
        "#{destination}.linear2_weight",
        :decision_head,
        [@hidden_size, @ffn_size]
      ),
      contract(
        "#{prefix}.linear2.bias",
        "#{destination}.linear2_bias",
        :decision_head,
        [@hidden_size]
      ),
      contract(
        "#{prefix}.norm1.weight",
        "#{destination}.norm1_weight",
        :decision_head,
        [@hidden_size]
      ),
      contract(
        "#{prefix}.norm1.bias",
        "#{destination}.norm1_bias",
        :decision_head,
        [@hidden_size]
      ),
      contract(
        "#{prefix}.norm2.weight",
        "#{destination}.norm2_weight",
        :decision_head,
        [@hidden_size]
      ),
      contract(
        "#{prefix}.norm2.bias",
        "#{destination}.norm2_bias",
        :decision_head,
        [@hidden_size]
      )
    ]
  end

  defp scorer_contract do
    [
      contract(
        "scorer.0.weight",
        "scorer_norm_weight",
        :scorer,
        [@hidden_size]
      ),
      contract(
        "scorer.0.bias",
        "scorer_norm_bias",
        :scorer,
        [@hidden_size]
      ),
      contract(
        "scorer.1.weight",
        "scorer_linear_weight",
        :scorer,
        [@hidden_size, @hidden_size]
      ),
      contract(
        "scorer.1.bias",
        "scorer_linear_bias",
        :scorer,
        [@hidden_size]
      ),
      contract(
        "scorer.3.weight",
        "scorer_output_weight",
        :scorer,
        [1, @hidden_size]
      ),
      contract(
        "scorer.3.bias",
        "scorer_output_bias",
        :scorer,
        [1]
      )
    ]
  end

  defp action_contract do
    [
      contract(
        "act_head.0.weight",
        "action_linear_weight",
        :act_head,
        [@action_hidden_size, @hidden_size + 4]
      ),
      contract(
        "act_head.0.bias",
        "action_linear_bias",
        :act_head,
        [@action_hidden_size]
      ),
      contract(
        "act_head.2.weight",
        "action_output_weight",
        :act_head,
        [2, @action_hidden_size]
      ),
      contract(
        "act_head.2.bias",
        "action_output_bias",
        :act_head,
        [2]
      )
    ]
  end

  defp contract(
         source,
         destination,
         family,
         shape
       ) do
    %{
      source: source,
      destination: destination,
      family: family,
      shape: shape,
      transform: :identity
    }
  end
end
