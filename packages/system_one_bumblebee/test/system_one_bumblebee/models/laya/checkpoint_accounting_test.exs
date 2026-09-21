defmodule SystemOneBumblebee.Models.Laya.CheckpointAccountingTest do
  alias SystemOneBumblebee.Models.Laya.DecisionHead
  use ExUnit.Case, async: true

  alias CrucibleSafetensors.TensorInfo
  alias SystemOneBumblebee.Models.Laya.CheckpointAccounting

  test "defines the exact reviewed source contract" do
    expected =
      CheckpointAccounting.expected_tensors()

    assert length(expected) == 206

    assert Enum.frequencies_by(
             expected,
             & &1.family
           ) == %{
             encoder: 170,
             decision_head: 24,
             type_emb: 1,
             scorer: 6,
             act_head: 4,
             temperature: 1
           }

    assert :ok =
             CheckpointAccounting.validate_plan()

    temperature =
      Enum.find(
        expected,
        &(&1.name == "temperature")
      )

    assert temperature.dtype == :f32
    assert temperature.shape == [3]
    assert temperature.nbytes == 12
  end

  test "encoder source names match the actual Laya namespace" do
    names =
      CheckpointAccounting.expected_tensors()
      |> Enum.map(& &1.name)
      |> MapSet.new()

    assert MapSet.member?(
             names,
             "encoder.embeddings.tok_embeddings.weight"
           )

    assert MapSet.member?(
             names,
             "encoder.layers.0.attn.Wqkv.weight"
           )

    assert MapSet.member?(
             names,
             "encoder.final_norm.weight"
           )

    refute Enum.any?(
             names,
             &String.starts_with?(
               &1,
               "encoder.model."
             )
           )
  end

  test "complete exact metadata produces 290 destination values" do
    assert {:ok, report} =
             exact_tensors()
             |> CheckpointAccounting.validate_tensors()

    assert report.status == :ok
    assert report.tensor_count == 206
    assert report.destination_count == 290
    assert report.destination_dtype == :f32
    assert report.issues == []

    assert report.family_counts == %{
             encoder: 170,
             decision_head: 24,
             type_emb: 1,
             scorer: 6,
             act_head: 4,
             temperature: 1
           }
  end

  test "reports missing source tensors" do
    [_removed | remaining] =
      exact_tensors()

    assert {:error, report} =
             CheckpointAccounting.validate_tensors(remaining)

    assert :tensor_count_mismatch in issue_codes(report)

    assert :missing_tensors in issue_codes(report)
  end

  test "reports unexpected source tensors" do
    [template | _] = exact_tensors()

    unexpected = %{
      template
      | name: "encoder.layers.28.attn.Wqkv.weight"
    }

    assert {:error, report} =
             CheckpointAccounting.validate_tensors([unexpected | exact_tensors()])

    assert :tensor_count_mismatch in issue_codes(report)

    assert :unexpected_tensors in issue_codes(report)
  end

  test "reports shape mismatches" do
    [tensor | rest] = exact_tensors()

    changed = %{
      tensor
      | shape: [1]
    }

    assert {:error, report} =
             CheckpointAccounting.validate_tensors([changed | rest])

    assert :shape_mismatch in issue_codes(report)
  end

  test "reports dtype mismatches" do
    [tensor | rest] = exact_tensors()

    changed = %{
      tensor
      | dtype: :f32
    }

    assert {:error, report} =
             CheckpointAccounting.validate_tensors([changed | rest])

    assert :dtype_mismatch in issue_codes(report)
  end

  test "reports duplicate source names" do
    [tensor | _] = exact_tensors()

    assert {:error, report} =
             CheckpointAccounting.validate_tensors([tensor | exact_tensors()])

    assert :duplicate_source_tensor in issue_codes(report)
  end

  test "reports unrecognized families" do
    [template | rest] = exact_tensors()

    changed = %{
      template
      | name: "mystery.weight"
    }

    assert {:error, report} =
             CheckpointAccounting.validate_tensors([changed | rest])

    assert :unrecognized_family in issue_codes(report)

    assert :missing_tensors in issue_codes(report)

    assert :unexpected_tensors in issue_codes(report)
  end

  test "rejects duplicate destination claims" do
    [first, second | rest] =
      CheckpointAccounting.expected_tensors()

    [claimed | _] =
      first.destinations

    second = %{
      second
      | destinations: [claimed | second.destinations]
    }

    assert {:error, issues} =
             CheckpointAccounting.validate_plan([first, second | rest])

    assert Enum.any?(
             issues,
             &(&1.code == :duplicate_destination)
           )
  end

  test "parameter destinations can be accounted as bf16 while temperature remains f32" do
    assert {:ok, report} =
             CheckpointAccounting.validate_tensors(
               exact_tensors(),
               destination_dtype: :bf16
             )

    destinations =
      Enum.flat_map(
        report.entries,
        & &1.destinations
      )

    temperature =
      Enum.find(
        destinations,
        &(&1.parameter ==
            "checkpoint_temperature")
      )

    parameters =
      Enum.reject(
        destinations,
        &(&1.parameter ==
            "checkpoint_temperature")
      )

    assert temperature.dtype == :f32

    assert Enum.all?(
             parameters,
             &(&1.dtype == :bf16)
           )
  end

  defp exact_tensors do
    CheckpointAccounting.expected_tensors()
    |> Enum.map_reduce(
      0,
      fn expected, offset ->
        tensor = %TensorInfo{
          name: expected.name,
          dtype: expected.dtype,
          shape: expected.shape,
          data_start: offset,
          data_end: offset + expected.nbytes,
          nbytes: expected.nbytes
        }

        {
          tensor,
          offset + expected.nbytes
        }
      end
    )
    |> elem(0)
  end

  defp issue_codes(report) do
    Enum.map(
      report.issues,
      & &1.code
    )
  end

  test "custom-head accounting is one-to-one with the permanent decision-head contract" do
    expectations =
      CheckpointAccounting.expected_tensors()

    custom =
      Enum.reject(
        expectations,
        &(&1.family == :encoder)
      )

    contract =
      DecisionHead.checkpoint_contract()

    assert length(custom) == 36
    assert length(contract) == 36

    assert Enum.all?(
             custom,
             &(length(&1.destinations) == 1)
           )

    accounting =
      Map.new(
        custom,
        fn expectation ->
          [destination] =
            expectation.destinations

          {
            expectation.name,
            %{
              family: expectation.family,
              source_shape: expectation.shape,
              source_dtype: expectation.dtype,
              parameter: destination.parameter,
              destination_shape: destination.shape,
              destination_dtype: destination.dtype,
              transform: destination.transform
            }
          }
        end
      )

    permanent =
      Map.new(
        contract,
        fn entry ->
          source_dtype =
            if entry.family == :temperature,
              do: :f32,
              else: :f16

          destination_dtype =
            if entry.family == :temperature,
              do: :f32,
              else: :parameter

          {
            entry.source,
            %{
              family: entry.family,
              source_shape: entry.shape,
              source_dtype: source_dtype,
              parameter: entry.destination,
              destination_shape: entry.shape,
              destination_dtype: destination_dtype,
              transform: entry.transform
            }
          }
        end
      )

    assert accounting == permanent
  end
end
