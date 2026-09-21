defmodule SystemOneBumblebee.Models.Laya.EncoderLoaderTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.EncoderLoader

  test "reviewed encoder destination contract contains 254 unique parameters" do
    assert {:ok, contract} =
             EncoderLoader.destination_contract(:f32)

    assert map_size(contract) == 254

    assert %{
             shape: [50_368, 1_024],
             type: {:f, 32},
             transform: :identity
           } =
             contract[
               "embedder.token_embedding.kernel"
             ]

    assert %{
             shape: [1_024, 1_024],
             type: {:f, 32},
             transform: :split_qkv_query_transpose
           } =
             contract[
               "encoder.blocks.0.self_attention.query.kernel"
             ]

    assert %{
             shape: [1_024, 2_624],
             type: {:f, 32},
             transform: :split_ffn_intermediate_transpose
           } =
             contract[
               "encoder.blocks.0.ffn.intermediate.kernel"
             ]
  end

  test "supports the deliberate Laya runtime parameter types" do
    assert {:ok, f16} =
             EncoderLoader.destination_contract(:f16)

    assert {:ok, bf16} =
             EncoderLoader.destination_contract(:bf16)

    assert {:ok, f32} =
             EncoderLoader.destination_contract(:f32)

    assert f16[
             "encoder.output_norm.weight"
           ].type == {:f, 16}

    assert bf16[
             "encoder.output_norm.weight"
           ].type == {:bf, 16}

    assert f32[
             "encoder.output_norm.weight"
           ].type == {:f, 32}
  end

  test "rejects unsupported runtime parameter types" do
    assert {:error, {:unsupported_laya_parameter_type, :s32}} =
             EncoderLoader.destination_contract(:s32)
  end

  test "load requires an explicit runtime parameter type" do
    assert {:error, :missing_laya_parameter_type} =
             EncoderLoader.load(
               "/does/not/matter",
               "/does/not/matter",
               []
             )
  end

  test "load rejects missing encoder directory after type validation" do
    assert {:error, {:missing_laya_encoder_directory, "/definitely/missing"}} =
             EncoderLoader.load(
               "/definitely/missing",
               "/also/missing",
               type: :f32
             )
  end
end
