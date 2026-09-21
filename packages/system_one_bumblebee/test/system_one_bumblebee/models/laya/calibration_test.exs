defmodule SystemOneBumblebee.Models.Laya.CalibrationTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.{Calibration, Config, Output}

  defp config do
    {:ok, config} =
      Config.decode(%{
        "encoder" => "answerdotai/ModernBERT-large",
        "head_layers" => 2,
        "max_len" => 512,
        "head_max_len" => 192,
        "max_prefixes" => 6,
        "amp_dtype" => "bf16",
        "temperature" => [1.0, 1.0, 1.0],
        "temperature_by_options" => %{}
      })

    config
  end

  test "softmax and confidence are finite and normalized" do
    assert {:ok, probabilities} = Calibration.probabilities([1.0, 2.0, 3.0], config(), "choice")
    assert_in_delta Enum.sum(probabilities), 1.0, 1.0e-12
    assert Calibration.confidence(probabilities) >= 0.0
    assert Calibration.confidence(probabilities) <= 1.0
    assert length(Calibration.features(probabilities)) == 4
  end

  test "choice output preserves criterion labels" do
    question = %{
      "type" => "choice",
      "instructions" => "route",
      "criteria" => Jason.OrderedObject.new([{"billing", "x"}, {"technical", "y"}])
    }

    assert {:ok, answer} = Output.answer(question, [4.0, 1.0], 0.25, config())
    assert answer["choice"] == "billing"
    assert Map.keys(answer["probabilities"]) |> Enum.sort() == ["billing", "technical"]
    assert answer["action"] == %{"act_probability" => 0.25}
  end

  test "noul returns calibrated true probability" do
    question = %{"type" => "noul", "instructions" => "is true?"}
    assert {:ok, answer} = Output.answer(question, [0.0, 2.0], 0.75, config())
    assert answer["noul"] > 0.5
    assert answer["confidence"] == answer["noul"]
  end
end
