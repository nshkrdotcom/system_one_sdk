defmodule SystemOneBumblebee.Models.Laya.ConfigTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.Config

  @config %{
    "encoder" => "answerdotai/ModernBERT-large",
    "head_layers" => 2,
    "max_len" => 512,
    "head_max_len" => 192,
    "max_prefixes" => 6,
    "amp_dtype" => "bf16",
    "model_name" => "rl-agent",
    "act_costs" => %{"escalate" => 0.5},
    "temperature" => [1.6369030475616455, 1.2514300346374512, 1.983399510383606],
    "temperature_by_options" => %{
      "choice:2" => 1.9063563346862793,
      "choice:3-5" => 1.7601518630981445,
      "choice:6-10" => 1.0000158548355103,
      "choice:11+" => 0.10058280825614929,
      "score:3-5" => 1.2514300346374512,
      "noul:2" => 1.983399510383606
    }
  }

  test "decodes the pinned English configuration semantics" do
    assert {:ok, config} = Config.decode(@config)
    assert config.encoder == "answerdotai/ModernBERT-large"
    assert config.head_layers == 2
    assert config.max_len == 512
    assert config.head_max_len == 192
    assert config.amp_dtype == "bf16"
    assert {:ok, 0} = Config.qtype_index("choice")
    assert {:ok, 1} = Config.qtype_index("score")
    assert {:ok, 2} = Config.qtype_index("noul")
  end

  test "uses option-count calibration buckets before base temperatures" do
    {:ok, config} = Config.decode(@config)
    assert {:ok, 1.9063563346862793} = Config.temperature_for(config, "choice", 2)
    assert {:ok, 1.7601518630981445} = Config.temperature_for(config, "choice", 4)
    assert {:ok, 1.0000158548355103} = Config.temperature_for(config, "choice", 8)
    assert {:ok, 0.10058280825614929} = Config.temperature_for(config, "choice", 11)
    assert {:ok, 1.2514300346374512} = Config.temperature_for(config, "score", 4)
    assert {:ok, 1.983399510383606} = Config.temperature_for(config, "noul", 2)
  end
end
