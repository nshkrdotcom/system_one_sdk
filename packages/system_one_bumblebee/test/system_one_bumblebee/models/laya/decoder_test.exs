defmodule SystemOneBumblebee.Models.Laya.DecoderTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.Decoder

  test "choice exactly follows upstream calibrated decoding semantics" do
    question = %{
      "type" => "choice",
      "instructions" => "Choose one.",
      "criteria" => [
        {"alpha", "Alpha"},
        {"beta", "Beta"},
        {"gamma", "Gamma"},
        {"delta", "Delta"},
        {"epsilon", "Epsilon"},
        {"zeta", "Zeta"}
      ]
    }

    probabilities = [
      0.11844535171985626,
      0.4454125761985779,
      0.21004818379878998,
      0.09326986968517303,
      0.05420340597629547,
      0.07862051576375961
    ]

    assert {:ok, answer} =
             Decoder.decode(
               question,
               probabilities,
               1.0
             )

    assert answer == %{
             "type" => "choice",
             "choice" => "beta",
             "probabilities" => %{
               "alpha" => 0.1184,
               "beta" => 0.4454,
               "gamma" => 0.21,
               "delta" => 0.0933,
               "epsilon" => 0.0542,
               "zeta" => 0.0786
             },
             "confidence" => 0.1517,
             "action" => %{
               "act_probability" => 1.0
             }
           }
  end

  test "choice preserves caller criterion order rather than sorting labels" do
    question = %{
      type: "choice",
      instructions: "Choose one.",
      criteria: [
        {"z", "first"},
        {"a", "second"}
      ]
    }

    assert {:ok, answer} =
             Decoder.decode(
               question,
               [0.9, 0.1],
               0.25
             )

    assert answer["choice"] == "z"

    assert answer[
             "probabilities"
           ] == %{
             "z" => 0.9,
             "a" => 0.1
           }
  end

  test "choice argmax uses the first option on an exact tie" do
    question = %{
      type: "choice",
      instructions: "Choose one.",
      criteria: [
        {"first", nil},
        {"second", nil}
      ]
    }

    answer =
      Decoder.decode!(
        question,
        [0.5, 0.5],
        0.5
      )

    assert answer[
             "choice"
           ] == "first"
  end

  test "score returns zero-based expected level, legend and distribution" do
    question = %{
      "type" => "score",
      "instructions" => "Rate severity.",
      "criteria" => [
        "none",
        "low",
        "medium",
        "high"
      ]
    }

    assert {:ok, answer} =
             Decoder.decode(
               question,
               [0.1, 0.2, 0.3, 0.4],
               0.37519
             )

    assert answer == %{
             "type" => "score",
             "score" => 2.0,
             "legend" => %{
               "0" => "none",
               "1" => "low",
               "2" => "medium",
               "3" => "high"
             },
             "probabilities" => %{
               "0" => 0.1,
               "1" => 0.2,
               "2" => 0.3,
               "3" => 0.4
             },
             "confidence" => 0.0768,
             "action" => %{
               "act_probability" => 0.3752
             }
           }
  end

  test "score legend preserves structured criterion values" do
    criterion = %{
      "name" => "critical",
      "page" => 2
    }

    question = %{
      type: "score",
      instructions: "Rate it.",
      criteria: [
        "low",
        criterion
      ]
    }

    answer =
      Decoder.decode!(
        question,
        [0.25, 0.75],
        0.5
      )

    assert answer[
             "legend"
           ][
             "1"
           ] == criterion

    assert answer[
             "score"
           ] == 0.75
  end

  test "noul returns probability of true and upstream native confidence" do
    question = %{
      "type" => "noul",
      "instructions" => "Does the statement hold?"
    }

    assert {:ok, answer} =
             Decoder.decode(
               question,
               [0.2, 0.8],
               0.61116
             )

    assert answer == %{
             "type" => "noul",
             "noul" => 0.8,
             "confidence" => 0.8,
             "action" => %{
               "act_probability" => 0.6112
             }
           }
  end

  test "noul confidence uses the more probable side" do
    question = %{
      type: "noul",
      instructions: "Does the statement hold?"
    }

    answer =
      Decoder.decode!(
        question,
        [0.91, 0.09],
        0.5
      )

    assert answer[
             "noul"
           ] == 0.09

    assert answer[
             "confidence"
           ] == 0.91
  end

  test "normalized entropy confidence matches the reference formula" do
    assert_in_delta(
      Decoder.confidence([0.1, 0.2, 0.3, 0.4]),
      0.07678032766449217,
      1.0e-12
    )

    assert Decoder.confidence([1.0]) == 1.0
  end

  test "rejects mismatched probability counts" do
    question = %{
      type: "score",
      instructions: "Rate it.",
      criteria: [
        "low",
        "high"
      ]
    }

    assert {:error,
            {:laya_probability_count_mismatch,
             %{
               expected: 2,
               actual: 1
             }}} =
             Decoder.decode(
               question,
               [1.0],
               0.5
             )
  end

  test "rejects values outside probability range" do
    question = %{
      type: "noul",
      instructions: "Does it hold?"
    }

    assert {:error, {:invalid_laya_probability, 1.1}} =
             Decoder.decode(
               question,
               [1.1, 0.0],
               0.5
             )

    assert {:error, {:invalid_laya_action_probability, -0.1}} =
             Decoder.decode(
               question,
               [0.5, 0.5],
               -0.1
             )
  end
end
