defmodule SystemOneBumblebee.Models.Laya.PythonJsonTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.Preprocessing

  test "structured state matches Python json.dumps spacing and unicode" do
    state =
      %Jason.OrderedObject{
        values: [
          {"city", "münchen"},
          {"nested", [1, 2]},
          {"enabled", true}
        ]
      }

    assert {:ok, ~s({"city": "münchen", "nested": [1, 2], "enabled": true})} =
             Preprocessing.serialize_state(state)
  end

  test "structured criterion matches Python render_criterion JSON" do
    criterion =
      %Jason.OrderedObject{
        values: [
          {"desc", "münchen"},
          {"weights", [1, 2]}
        ]
      }

    assert {:ok, ~s({"desc": "münchen", "weights": [1, 2]})} =
             Preprocessing.render_criterion(criterion)
  end

  test "structured instructions use Python json.dumps default ASCII escaping" do
    question = %{
      type: "noul",
      instructions: %Jason.OrderedObject{
        values: [
          {"city", "münchen"},
          {"active", true}
        ]
      }
    }

    assert {:ok, ~S(noul question: {"city": "m\u00fcnchen", "active": true})} =
             Preprocessing.render_question(question)
  end
end
