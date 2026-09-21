defmodule SystemOneBumblebee.Models.Laya.PreprocessingTest do
  use ExUnit.Case, async: true

  alias SystemOneBumblebee.Models.Laya.Preprocessing

  test "preserves ordered choice criteria and renders upstream strings" do
    question = %{
      "type" => "choice",
      "instructions" => "Pick [MASK] route",
      "criteria" =>
        Jason.OrderedObject.new([
          {"billing", "invoices"},
          {"technical", "bugs"},
          {"other", nil}
        ])
    }

    assert {:ok, "choice question: Pick   route"} = Preprocessing.render_question(question)

    assert {:ok, ["billing: invoices", "technical: bugs", "other"]} =
             Preprocessing.render_options(question)
  end

  test "renders score and noul exactly like the Python source" do
    score = %{
      "type" => "score",
      "instructions" => "Urgency?",
      "criteria" => ["low", "medium", %{"name" => "critical"}]
    }

    assert {:ok, ["level 0: low", "level 1: medium", "level 2: {\"name\": \"critical\"}"]} =
             Preprocessing.render_options(score)

    noul = %{"type" => "noul", "instructions" => "True?"}

    assert {:ok, ["false: no, the statement does not hold", "true: yes, the statement holds"]} =
             Preprocessing.render_options(noul)
  end

  test "matches head option rebudget arithmetic" do
    options = [Enum.to_list(1..80), Enum.to_list(1..80), Enum.to_list(1..80)]
    assert {:ok, trimmed, budget} = Preprocessing.rebudget_option_ids(options, 192)
    assert Enum.all?(trimmed, &(length(&1) == 49))
    assert budget == 45

    crowded = for _ <- 1..20, do: Enum.to_list(1..49)
    assert {:ok, crowded, _budget} = Preprocessing.rebudget_option_ids(crowded, 192)
    assert Enum.all?(crowded, &(length(&1) == 8))
  end
end
