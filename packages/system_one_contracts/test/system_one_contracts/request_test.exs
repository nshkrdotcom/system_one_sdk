defmodule SystemOneContracts.RequestTest do
  use ExUnit.Case, async: true

  alias SystemOneContracts.V1.Request

  test "pair-list questions preserve their wire order" do
    request =
      Request.new!(
        %{"ticket" => 7},
        [
          {"route",
           %{
             "type" => "choice",
             "criteria" => Jason.OrderedObject.new([{"z", nil}, {"a", nil}])
           }},
          {"urgent", %{"type" => "noul"}}
        ],
        "model-a"
      )

    assert Request.question_keys(request) == ["route", "urgent"]

    json = Request.encode!(request)
    assert json =~ ~s("questions":{"route":)
    assert json =~ ~s("criteria":{"z":null,"a":null})
  end

  test "maps use deterministic question-key ordering" do
    request =
      Request.new!(
        "state",
        %{"z" => %{"type" => "noul"}, "a" => %{"type" => "noul"}},
        "model-a"
      )

    assert Request.question_keys(request) == ["a", "z"]
  end

  test "raw JSON decoding preserves nested Choice criteria order" do
    json =
      ~s({"state":{"ticket":7},"model":"model-a","questions":) <>
        ~s({"route":{"type":"choice","criteria":{"z":"Z first","a":"A second"}}}})

    assert {:ok, request} = Request.decode_json(json)
    route = request.questions |> Enum.into(%{}) |> Map.fetch!("route")
    criteria = SystemOneContracts.V1.Validation.value(route, "criteria")

    assert %Jason.OrderedObject{values: [{"z", "Z first"}, {"a", "A second"}]} = criteria
    assert Request.encode!(request) =~ ~s("criteria":{"z":"Z first","a":"A second"})
  end
end
