defmodule SystemOneBumblebee.Models.Laya.DecisionHeadLoader do
  @moduledoc """
  Strict SafeTensors loader for Laya's trained custom decision head.

  The encoder is intentionally excluded; its checkpoint mapping is
  handled by `EncoderLoader` and Bumblebee.

  The custom head preserves the PyTorch source parameter layout exactly,
  so each trained custom-head source tensor maps one-to-one to one
  runtime tensor.
  """

  alias CrucibleSafetensors.{
    Reader,
    Slice,
    TensorInfo
  }

  alias SystemOneBumblebee.Models.Laya.DecisionHead

  @source_count 35

  @type loaded :: %{
          params: map(),
          checkpoint_temperature: Nx.Tensor.t(),
          source_count: pos_integer(),
          parameter_type: Nx.Type.t()
        }

  @doc """
  Loads all 35 trained custom-head parameters plus the independent
  three-value checkpoint temperature buffer.

  Options:

    * `:backend` - target Nx backend, defaults to `Nx.BinaryBackend`;
    * `:type` - runtime parameter type, defaults to `:f32`.

  The source checkpoint remains unchanged.
  """
  @spec load(Path.t(), keyword()) ::
          {:ok, loaded()}
          | {:error, term()}
  def load(
        checkpoint_path,
        opts \\ []
      )
      when is_binary(checkpoint_path) do
    opts =
      Keyword.validate!(
        opts,
        backend: Nx.BinaryBackend,
        type: :f32
      )

    backend =
      Keyword.fetch!(
        opts,
        :backend
      )

    parameter_type =
      opts
      |> Keyword.fetch!(:type)
      |> normalize_type!()

    do_load(
      checkpoint_path,
      backend,
      parameter_type
    )
  rescue
    error ->
      {:error, {:decision_head_load_failed, Exception.message(error)}}
  end

  @doc """
  Same as `load/2`, raising on failure.
  """
  @spec load!(Path.t(), keyword()) :: loaded()
  def load!(
        checkpoint_path,
        opts \\ []
      ) do
    case load(
           checkpoint_path,
           opts
         ) do
      {:ok, loaded} ->
        loaded

      {:error, reason} ->
        raise ArgumentError,
              "failed to load Laya decision head: " <>
                inspect(reason)
    end
  end

  defp do_load(
         checkpoint_path,
         backend,
         parameter_type
       ) do
    header =
      Reader.open!(checkpoint_path)

    contract =
      DecisionHead.source_contract()

    validate_contract!(
      header,
      contract
    )

    loaded =
      Map.new(
        contract,
        fn entry ->
          {
            entry.source,
            read_parameter!(
              header,
              entry,
              backend,
              parameter_type
            )
          }
        end
      )

    checkpoint_temperature =
      read_checkpoint_temperature!(
        header,
        backend
      )

    params = %{
      type_embedding:
        fetch!(
          loaded,
          "type_emb.weight"
        ),
      layer0:
        layer_params(
          loaded,
          0
        ),
      layer1:
        layer_params(
          loaded,
          1
        ),
      scorer_norm_weight:
        fetch!(
          loaded,
          "scorer.0.weight"
        ),
      scorer_norm_bias:
        fetch!(
          loaded,
          "scorer.0.bias"
        ),
      scorer_linear_weight:
        fetch!(
          loaded,
          "scorer.1.weight"
        ),
      scorer_linear_bias:
        fetch!(
          loaded,
          "scorer.1.bias"
        ),
      scorer_output_weight:
        fetch!(
          loaded,
          "scorer.3.weight"
        ),
      scorer_output_bias:
        fetch!(
          loaded,
          "scorer.3.bias"
        ),
      action_linear_weight:
        fetch!(
          loaded,
          "act_head.0.weight"
        ),
      action_linear_bias:
        fetch!(
          loaded,
          "act_head.0.bias"
        ),
      action_output_weight:
        fetch!(
          loaded,
          "act_head.2.weight"
        ),
      action_output_bias:
        fetch!(
          loaded,
          "act_head.2.bias"
        )
    }

    {:ok,
     %{
       params: params,
       checkpoint_temperature: checkpoint_temperature,
       source_count: map_size(loaded),
       parameter_type: parameter_type
     }}
  end

  defp validate_contract!(
         header,
         contract
       ) do
    expected_names =
      contract
      |> Enum.map(& &1.source)
      |> MapSet.new()

    actual_names =
      header.tensors
      |> Map.keys()
      |> Enum.filter(&custom_head_source?/1)
      |> MapSet.new()

    missing =
      MapSet.difference(
        expected_names,
        actual_names
      )
      |> MapSet.to_list()
      |> Enum.sort()

    unexpected =
      MapSet.difference(
        actual_names,
        expected_names
      )
      |> MapSet.to_list()
      |> Enum.sort()

    cond do
      length(contract) != @source_count ->
        raise ArgumentError,
              "expected #{@source_count} custom-head contract entries, " <>
                "got #{length(contract)}"

      missing != [] ->
        raise ArgumentError,
              "missing custom-head checkpoint tensors: " <>
                inspect(missing)

      unexpected != [] ->
        raise ArgumentError,
              "unexpected custom-head checkpoint tensors: " <>
                inspect(unexpected)

      true ->
        Enum.each(
          contract,
          &validate_entry!(
            header,
            &1
          )
        )
    end
  end

  defp validate_entry!(
         header,
         entry
       ) do
    %TensorInfo{} =
      tensor_info =
      Map.fetch!(
        header.tensors,
        entry.source
      )

    cond do
      tensor_info.shape != entry.shape ->
        raise ArgumentError,
              "shape mismatch for #{entry.source}: " <>
                "expected #{inspect(entry.shape)}, " <>
                "got #{inspect(tensor_info.shape)}"

      tensor_info.dtype != :f16 ->
        raise ArgumentError,
              "dtype mismatch for #{entry.source}: " <>
                "expected :f16, got #{inspect(tensor_info.dtype)}"

      true ->
        :ok
    end
  end

  defp read_parameter!(
         header,
         entry,
         backend,
         parameter_type
       ) do
    %TensorInfo{} =
      tensor_info =
      Map.fetch!(
        header.tensors,
        entry.source
      )

    tensor_info
    |> read_tensor!(header)
    |> Nx.as_type(parameter_type)
    |> Nx.backend_transfer(backend)
  end

  defp read_checkpoint_temperature!(
         header,
         backend
       ) do
    %TensorInfo{} =
      tensor_info =
      Map.fetch!(
        header.tensors,
        "temperature"
      )

    unless tensor_info.shape == [3] do
      raise ArgumentError,
            "temperature shape mismatch: expected [3], got " <>
              inspect(tensor_info.shape)
    end

    unless tensor_info.dtype == :f32 do
      raise ArgumentError,
            "temperature dtype mismatch: expected :f32, got " <>
              inspect(tensor_info.dtype)
    end

    tensor_info
    |> read_tensor!(header)
    |> Nx.as_type(:f32)
    |> Nx.backend_transfer(backend)
  end

  defp read_tensor!(
         %TensorInfo{} = tensor_info,
         header
       ) do
    %Slice{} =
      slice =
      case Reader.read_tensor(
             header,
             tensor_info
           ) do
        {:ok, value} ->
          value

        {:error, reason} ->
          raise reason
      end

    slice.data
    |> Nx.from_binary(source_nx_type!(tensor_info.dtype))
    |> Nx.reshape(List.to_tuple(tensor_info.shape))
  end

  defp layer_params(
         loaded,
         index
       ) do
    prefix =
      "head.layers.#{index}"

    %{
      in_proj_weight:
        fetch!(
          loaded,
          "#{prefix}.self_attn.in_proj_weight"
        ),
      in_proj_bias:
        fetch!(
          loaded,
          "#{prefix}.self_attn.in_proj_bias"
        ),
      out_proj_weight:
        fetch!(
          loaded,
          "#{prefix}.self_attn.out_proj.weight"
        ),
      out_proj_bias:
        fetch!(
          loaded,
          "#{prefix}.self_attn.out_proj.bias"
        ),
      linear1_weight:
        fetch!(
          loaded,
          "#{prefix}.linear1.weight"
        ),
      linear1_bias:
        fetch!(
          loaded,
          "#{prefix}.linear1.bias"
        ),
      linear2_weight:
        fetch!(
          loaded,
          "#{prefix}.linear2.weight"
        ),
      linear2_bias:
        fetch!(
          loaded,
          "#{prefix}.linear2.bias"
        ),
      norm1_weight:
        fetch!(
          loaded,
          "#{prefix}.norm1.weight"
        ),
      norm1_bias:
        fetch!(
          loaded,
          "#{prefix}.norm1.bias"
        ),
      norm2_weight:
        fetch!(
          loaded,
          "#{prefix}.norm2.weight"
        ),
      norm2_bias:
        fetch!(
          loaded,
          "#{prefix}.norm2.bias"
        )
    }
  end

  defp custom_head_source?("type_emb.weight"),
    do: true

  defp custom_head_source?("head.layers." <> _),
    do: true

  defp custom_head_source?("scorer." <> _),
    do: true

  defp custom_head_source?("act_head." <> _),
    do: true

  defp custom_head_source?(_),
    do: false

  defp fetch!(
         loaded,
         name
       ) do
    Map.fetch!(
      loaded,
      name
    )
  end

  defp normalize_type!(:f32),
    do: {:f, 32}

  defp normalize_type!(:f16),
    do: {:f, 16}

  defp normalize_type!(:bf16),
    do: {:bf, 16}

  defp normalize_type!({:f, 32} = type),
    do: type

  defp normalize_type!({:f, 16} = type),
    do: type

  defp normalize_type!({:bf, 16} = type),
    do: type

  defp normalize_type!(other) do
    raise ArgumentError,
          "unsupported Laya decision-head parameter type: " <>
            inspect(other)
  end

  defp source_nx_type!(:f16),
    do: {:f, 16}

  defp source_nx_type!(:bf16),
    do: {:bf, 16}

  defp source_nx_type!(:f32),
    do: {:f, 32}

  defp source_nx_type!(:i32),
    do: {:s, 32}

  defp source_nx_type!(:i64),
    do: {:s, 64}
end
