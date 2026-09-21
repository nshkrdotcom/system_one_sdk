defmodule SystemOneBumblebee.Models.Laya.InventoryTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.Inventory

  test "summarizes checkpoint tensor families without loading tensor bytes" do
    inventory =
      Enum.map(1..170, &%{name: "encoder.layer#{&1}", dtype: :f16}) ++
        [%{name: "type_emb.weight", dtype: :f16}] ++
        Enum.map(1..6, &%{name: "scorer.#{&1}", dtype: :f16}) ++
        Enum.map(1..4, &%{name: "act_head.#{&1}", dtype: :f16}) ++
        Enum.map(1..25, &%{name: "head.#{&1}", dtype: :f16})

    summary = Inventory.summarize(inventory)
    assert summary.tensor_count == 206
    assert summary.families.encoder == 170
    assert summary.families.type_emb == 1
    assert summary.families.scorer == 6
    assert summary.families.act_head == 4
    assert Inventory.expected_english_shape?(summary)
  end
end
