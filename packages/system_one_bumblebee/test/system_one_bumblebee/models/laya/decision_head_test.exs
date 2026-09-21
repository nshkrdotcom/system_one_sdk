defmodule SystemOneBumblebee.Models.Laya.DecisionHeadTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.DecisionHead

  test "custom-head contract matches the real checkpoint families" do
    contract =
      DecisionHead.checkpoint_contract()

    assert length(contract) == 36

    assert contract
           |> Enum.map(& &1.source)
           |> Enum.uniq()
           |> length() == 36

    assert contract
           |> Enum.map(& &1.destination)
           |> Enum.uniq()
           |> length() == 36

    counts =
      Enum.frequencies_by(
        contract,
        & &1.family
      )

    assert counts == %{
             type_emb: 1,
             decision_head: 24,
             scorer: 6,
             act_head: 4,
             temperature: 1
           }
  end

  test "custom head preserves PyTorch parameter layout" do
    contract =
      DecisionHead.source_contract()

    assert length(contract) == 35

    assert Enum.all?(
             contract,
             &(&1.transform == :identity)
           )

    qkv =
      Enum.find(
        contract,
        &(&1.source ==
            "head.layers.0.self_attn.in_proj_weight")
      )

    assert qkv.shape == [3_072, 1_024]

    assert qkv.destination ==
             "layer0.in_proj_weight"

    linear1 =
      Enum.find(
        contract,
        &(&1.source ==
            "head.layers.0.linear1.weight")
      )

    assert linear1.shape == [4_096, 1_024]

    linear2 =
      Enum.find(
        contract,
        &(&1.source ==
            "head.layers.0.linear2.weight")
      )

    assert linear2.shape == [1_024, 4_096]
  end

  test "calibration helper applies temperature before softmax" do
    logits =
      Nx.tensor(
        [[1.0, 2.0, 3.0]],
        type: :f32
      )

    temperature =
      Nx.tensor(
        2.0,
        type: :f32
      )

    probabilities =
      DecisionHead.calibrated_probabilities(
        logits,
        temperature
      )
      |> Nx.to_flat_list()

    expected =
      [0.18632372, 0.30719590, 0.50648040]

    Enum.zip(
      probabilities,
      expected
    )
    |> Enum.each(fn {actual, wanted} ->
      assert_in_delta(
        actual,
        wanted,
        1.0e-6
      )
    end)
  end

  test "action probability helper uses ordinary softmax" do
    logits =
      Nx.tensor(
        [[2.0, 1.0]],
        type: :f32
      )

    probabilities =
      DecisionHead.action_probabilities(logits)
      |> Nx.to_flat_list()

    assert_in_delta(
      Enum.at(probabilities, 0),
      0.7310586,
      1.0e-6
    )

    assert_in_delta(
      Enum.at(probabilities, 1),
      0.2689414,
      1.0e-6
    )
  end
end
