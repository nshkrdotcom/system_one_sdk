defmodule SystemOneBumblebee.Models.Laya.CheckpointAccounting do
  alias SystemOneBumblebee.Models.Laya.DecisionHead

  @moduledoc """
  Strict checkpoint accounting for the reviewed English Laya model.

  The checkpoint contains exactly 206 source tensors. This module records the
  exact source names, storage dtypes, shapes and intended native destination
  transformations before any model allocation occurs.
  """

  alias CrucibleSafetensors.{Reader, TensorInfo}

  @expected_tensor_count 206

  @expected_family_counts %{
    encoder: 170,
    decision_head: 24,
    type_emb: 1,
    scorer: 6,
    act_head: 4,
    temperature: 1
  }

  @type family ::
          :encoder
          | :decision_head
          | :type_emb
          | :scorer
          | :act_head
          | :temperature
          | :unrecognized

  @type destination :: %{
          required(:parameter) => String.t(),
          required(:transform) => atom(),
          required(:shape) => [pos_integer()],
          required(:dtype) => atom()
        }

  @type expectation :: %{
          required(:name) => String.t(),
          required(:family) => family(),
          required(:dtype) => atom(),
          required(:shape) => [pos_integer()],
          required(:nbytes) => pos_integer(),
          required(:destinations) => [destination()]
        }

  @doc "Returns the exact reviewed source tensor count."
  @spec expected_tensor_count() :: pos_integer()
  def expected_tensor_count, do: @expected_tensor_count

  @doc "Returns the exact reviewed source family counts."
  @spec expected_family_counts() :: map()
  def expected_family_counts, do: @expected_family_counts

  @doc "Returns the complete source-to-destination checkpoint plan."
  @spec expected_tensors() :: [expectation()]
  def expected_tensors do
    [
      encoder_expectations(),
      custom_head_expectations()
    ]
    |> List.flatten()
  end

  @doc "Validates the default source-to-destination plan."
  @spec validate_plan() :: :ok | {:error, [map()]}
  def validate_plan do
    validate_plan(expected_tensors())
  end

  @doc "Validates a source-to-destination plan."
  @spec validate_plan([expectation()]) ::
          :ok | {:error, [map()]}
  def validate_plan(plan) when is_list(plan) do
    case plan_issues(plan) do
      [] -> :ok
      issues -> {:error, issues}
    end
  end

  @doc "Validates a SafeTensors checkpoint against the reviewed contract."
  @spec validate_file(Path.t()) ::
          {:ok, map()} | {:error, map()}
  def validate_file(path) do
    validate_file(path, [])
  end

  @doc "Validates a SafeTensors checkpoint with accounting options."
  @spec validate_file(Path.t(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def validate_file(path, opts) when is_binary(path) do
    case Reader.open(path) do
      {:ok, header} ->
        header.tensors
        |> Map.values()
        |> validate_tensors(opts)

      {:error, reason} ->
        {:error,
         %{
           status: :error,
           tensor_count: 0,
           issues: [
             %{
               code: :checkpoint_read_failed,
               reason: inspect(reason)
             }
           ]
         }}
    end
  end

  @doc "Validates source tensor metadata against the reviewed contract."
  @spec validate_tensors([TensorInfo.t()]) ::
          {:ok, map()} | {:error, map()}
  def validate_tensors(tensors) do
    validate_tensors(tensors, [])
  end

  @doc "Validates source tensor metadata with accounting options."
  @spec validate_tensors([TensorInfo.t()], keyword()) ::
          {:ok, map()} | {:error, map()}
  def validate_tensors(tensors, opts)
      when is_list(tensors) do
    plan =
      Keyword.get(
        opts,
        :plan,
        expected_tensors()
      )

    destination_dtype =
      Keyword.get(
        opts,
        :destination_dtype,
        :f32
      )

    issues =
      plan_issues(plan) ++
        source_issues(tensors, plan)

    report =
      build_report(
        tensors,
        plan,
        destination_dtype,
        issues
      )

    if issues == [] do
      {:ok, report}
    else
      {:error, report}
    end
  end

  @doc "Classifies a source tensor name into a checkpoint family."
  @spec family(String.t()) :: family()
  def family("encoder." <> _rest), do: :encoder
  def family("head." <> _rest), do: :decision_head
  def family("type_emb." <> _rest), do: :type_emb
  def family("scorer." <> _rest), do: :scorer
  def family("act_head." <> _rest), do: :act_head
  def family("temperature"), do: :temperature
  def family(_name), do: :unrecognized

  defp encoder_expectations do
    fixed = [
      expectation(
        "encoder.embeddings.tok_embeddings.weight",
        :encoder,
        :f16,
        [50_368, 1_024],
        [
          destination(
            "embedder.token_embedding.kernel",
            :identity,
            [50_368, 1_024]
          )
        ]
      ),
      expectation(
        "encoder.embeddings.norm.weight",
        :encoder,
        :f16,
        [1_024],
        [
          destination(
            "embedder.norm.weight",
            :identity,
            [1_024]
          )
        ]
      ),
      expectation(
        "encoder.final_norm.weight",
        :encoder,
        :f16,
        [1_024],
        [
          destination(
            "encoder.output_norm.weight",
            :identity,
            [1_024]
          )
        ]
      )
    ]

    blocks =
      Enum.flat_map(
        0..27,
        &encoder_block_expectations/1
      )

    fixed ++ blocks
  end

  defp encoder_block_expectations(index) do
    source = "encoder.layers.#{index}"
    target = "encoder.blocks.#{index}"

    core = [
      expectation(
        "#{source}.attn.Wqkv.weight",
        :encoder,
        :f16,
        [3_072, 1_024],
        [
          destination(
            "#{target}.self_attention.query.kernel",
            :split_qkv_query_transpose,
            [1_024, 1_024]
          ),
          destination(
            "#{target}.self_attention.key.kernel",
            :split_qkv_key_transpose,
            [1_024, 1_024]
          ),
          destination(
            "#{target}.self_attention.value.kernel",
            :split_qkv_value_transpose,
            [1_024, 1_024]
          )
        ]
      ),
      expectation(
        "#{source}.attn.Wo.weight",
        :encoder,
        :f16,
        [1_024, 1_024],
        [
          destination(
            "#{target}.self_attention.output.kernel",
            :transpose,
            [1_024, 1_024]
          )
        ]
      ),
      expectation(
        "#{source}.mlp.Wi.weight",
        :encoder,
        :f16,
        [5_248, 1_024],
        [
          destination(
            "#{target}.ffn.intermediate.kernel",
            :split_ffn_intermediate_transpose,
            [1_024, 2_624]
          ),
          destination(
            "#{target}.ffn.gate.kernel",
            :split_ffn_gate_transpose,
            [1_024, 2_624]
          )
        ]
      ),
      expectation(
        "#{source}.mlp.Wo.weight",
        :encoder,
        :f16,
        [1_024, 2_624],
        [
          destination(
            "#{target}.ffn.output.kernel",
            :transpose,
            [2_624, 1_024]
          )
        ]
      ),
      expectation(
        "#{source}.mlp_norm.weight",
        :encoder,
        :f16,
        [1_024],
        [
          destination(
            "#{target}.output_norm.weight",
            :identity,
            [1_024]
          )
        ]
      )
    ]

    if index == 0 do
      core
    else
      [
        expectation(
          "#{source}.attn_norm.weight",
          :encoder,
          :f16,
          [1_024],
          [
            destination(
              "#{target}.self_attention_norm.weight",
              :identity,
              [1_024]
            )
          ]
        )
        | core
      ]
    end
  end

  defp custom_head_expectations do
    DecisionHead.checkpoint_contract()
    |> Enum.map(&custom_head_expectation/1)
  end

  defp custom_head_expectation(entry) do
    expectation(
      entry.source,
      entry.family,
      custom_source_dtype(entry.family),
      entry.shape,
      [
        %{
          parameter: entry.destination,
          transform: entry.transform,
          shape: entry.shape,
          dtype: custom_destination_dtype(entry.family)
        }
      ]
    )
  end

  defp custom_source_dtype(:temperature),
    do: :f32

  defp custom_source_dtype(_family),
    do: :f16

  defp custom_destination_dtype(:temperature),
    do: :f32

  defp custom_destination_dtype(_family),
    do: :parameter

  defp expectation(
         name,
         family,
         dtype,
         shape,
         destinations
       ) do
    %{
      name: name,
      family: family,
      dtype: dtype,
      shape: shape,
      nbytes: tensor_nbytes(shape, dtype),
      destinations: destinations
    }
  end

  defp destination(
         parameter,
         transform,
         shape,
         dtype \\ :parameter
       ) do
    %{
      parameter: parameter,
      transform: transform,
      shape: shape,
      dtype: dtype
    }
  end

  defp tensor_nbytes(shape, dtype) do
    Enum.product(shape) * dtype_bytes(dtype)
  end

  defp dtype_bytes(:f16), do: 2
  defp dtype_bytes(:f32), do: 4

  defp plan_issues(plan) do
    source_names =
      Enum.map(
        plan,
        & &1.name
      )

    destination_names =
      Enum.flat_map(
        plan,
        fn expected ->
          Enum.map(
            expected.destinations,
            & &1.parameter
          )
        end
      )

    family_counts =
      Enum.frequencies_by(
        plan,
        & &1.family
      )

    []
    |> maybe_add_duplicate_issue(
      :duplicate_planned_source,
      source_names
    )
    |> maybe_add_duplicate_issue(
      :duplicate_destination,
      destination_names
    )
    |> maybe_add_plan_count_issue(plan)
    |> maybe_add_plan_family_issue(family_counts)
  end

  defp maybe_add_duplicate_issue(
         issues,
         code,
         values
       ) do
    duplicates =
      values
      |> Enum.frequencies()
      |> Enum.filter(fn {_value, count} ->
        count > 1
      end)
      |> Enum.map(fn {value, count} ->
        %{
          value: value,
          count: count
        }
      end)
      |> Enum.sort_by(& &1.value)

    if duplicates == [] do
      issues
    else
      issues ++
        [
          %{
            code: code,
            duplicates: duplicates
          }
        ]
    end
  end

  defp maybe_add_plan_count_issue(
         issues,
         plan
       ) do
    actual = length(plan)

    if actual == @expected_tensor_count do
      issues
    else
      issues ++
        [
          %{
            code: :plan_tensor_count_mismatch,
            expected: @expected_tensor_count,
            actual: actual
          }
        ]
    end
  end

  defp maybe_add_plan_family_issue(
         issues,
         @expected_family_counts
       ),
       do: issues

  defp maybe_add_plan_family_issue(
         issues,
         actual
       ) do
    issues ++
      [
        %{
          code: :plan_family_count_mismatch,
          expected: @expected_family_counts,
          actual: actual
        }
      ]
  end

  defp source_issues(tensors, plan) do
    actual_names =
      Enum.map(
        tensors,
        & &1.name
      )

    expected_names =
      Enum.map(
        plan,
        & &1.name
      )

    expected_set =
      MapSet.new(expected_names)

    actual_set =
      MapSet.new(actual_names)

    missing =
      expected_set
      |> MapSet.difference(actual_set)
      |> MapSet.to_list()
      |> Enum.sort()

    unexpected =
      actual_set
      |> MapSet.difference(expected_set)
      |> MapSet.to_list()
      |> Enum.sort()

    unrecognized =
      actual_names
      |> Enum.filter(&(family(&1) == :unrecognized))
      |> Enum.uniq()
      |> Enum.sort()

    []
    |> maybe_add_source_count_issue(tensors)
    |> maybe_add_duplicate_issue(
      :duplicate_source_tensor,
      actual_names
    )
    |> maybe_add_name_issue(
      :missing_tensors,
      missing
    )
    |> maybe_add_name_issue(
      :unexpected_tensors,
      unexpected
    )
    |> maybe_add_name_issue(
      :unrecognized_family,
      unrecognized
    )
    |> Kernel.++(
      tensor_mismatch_issues(
        tensors,
        plan
      )
    )
  end

  defp maybe_add_source_count_issue(
         issues,
         tensors
       ) do
    actual = length(tensors)

    if actual == @expected_tensor_count do
      issues
    else
      issues ++
        [
          %{
            code: :tensor_count_mismatch,
            expected: @expected_tensor_count,
            actual: actual
          }
        ]
    end
  end

  defp maybe_add_name_issue(
         issues,
         _code,
         []
       ),
       do: issues

  defp maybe_add_name_issue(
         issues,
         code,
         names
       ) do
    issues ++
      [
        %{
          code: code,
          names: names
        }
      ]
  end

  defp tensor_mismatch_issues(
         tensors,
         plan
       ) do
    actual_by_name =
      Map.new(
        tensors,
        &{&1.name, &1}
      )

    Enum.flat_map(
      plan,
      fn expected ->
        case Map.get(
               actual_by_name,
               expected.name
             ) do
          nil ->
            []

          actual ->
            compare_tensor(
              actual,
              expected
            )
        end
      end
    )
  end

  defp compare_tensor(
         actual,
         expected
       ) do
    []
    |> maybe_add_mismatch(
      :dtype_mismatch,
      actual.name,
      expected.dtype,
      actual.dtype
    )
    |> maybe_add_mismatch(
      :shape_mismatch,
      actual.name,
      expected.shape,
      actual.shape
    )
    |> maybe_add_mismatch(
      :byte_count_mismatch,
      actual.name,
      expected.nbytes,
      actual.nbytes
    )
  end

  defp maybe_add_mismatch(
         issues,
         _code,
         _name,
         value,
         value
       ),
       do: issues

  defp maybe_add_mismatch(
         issues,
         code,
         name,
         expected,
         actual
       ) do
    issues ++
      [
        %{
          code: code,
          tensor: name,
          expected: expected,
          actual: actual
        }
      ]
  end

  defp build_report(
         tensors,
         plan,
         destination_dtype,
         issues
       ) do
    plan_by_name =
      Map.new(
        plan,
        &{&1.name, &1}
      )

    entries =
      tensors
      |> Enum.sort_by(& &1.name)
      |> Enum.map(fn tensor ->
        expected =
          Map.get(
            plan_by_name,
            tensor.name
          )

        %{
          source: %{
            name: tensor.name,
            family: family(tensor.name),
            dtype: tensor.dtype,
            shape: tensor.shape,
            nbytes: tensor.nbytes
          },
          destinations:
            report_destinations(
              expected,
              destination_dtype
            )
        }
      end)

    family_counts =
      Enum.frequencies_by(
        tensors,
        &family(&1.name)
      )

    destination_count =
      Enum.reduce(
        plan,
        0,
        fn expected, total ->
          total +
            length(expected.destinations)
        end
      )

    %{
      status:
        if(
          issues == [],
          do: :ok,
          else: :error
        ),
      tensor_count: length(tensors),
      expected_tensor_count: @expected_tensor_count,
      family_counts: family_counts,
      expected_family_counts: @expected_family_counts,
      source_bytes:
        Enum.reduce(
          tensors,
          0,
          &(&1.nbytes + &2)
        ),
      destination_count: destination_count,
      destination_dtype: destination_dtype,
      entries: entries,
      issues: issues
    }
  end

  defp report_destinations(
         nil,
         _destination_dtype
       ),
       do: []

  defp report_destinations(
         expected,
         destination_dtype
       ) do
    Enum.map(
      expected.destinations,
      fn destination ->
        dtype =
          case destination.dtype do
            :parameter ->
              destination_dtype

            explicit ->
              explicit
          end

        %{destination | dtype: dtype}
      end
    )
  end
end
