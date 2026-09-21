defmodule SystemOneBumblebee.ProviderTest do
  use ExUnit.Case, async: false

  alias SystemOneBumblebee.{Adapters.Fake, Provider, RuntimeProfile}
  alias SystemOneContracts.Conformance
  alias SystemOneContracts.V1.Request

  setup do
    model = "fixture-#{System.unique_integer([:positive])}"
    alias_name = model <> "-alias"

    assert {:ok, state} =
             Provider.new(
               models: %{
                 model => %{
                   adapter: Fake,
                   aliases: [alias_name],
                   description: "offline deterministic provider fixture"
                 }
               },
               runtime_profile: RuntimeProfile.test()
             )

    %{model: model, alias_name: alias_name, state: state}
  end

  test "implements reusable contracts conformance", %{model: model, state: state} do
    assert {:ok, report} = Conformance.run(Provider, state, model: model)
    assert report.protocol == SystemOneContracts.protocol()
    assert report.provider == :system_one_bumblebee
    assert report.model == model
  end

  test "aliases resolve to the canonical response model", %{
    model: model,
    alias_name: alias_name,
    state: state
  } do
    questions = [
      {"decision", %{"type" => "noul", "instructions" => "fixture"}}
    ]

    assert {:ok, request} = Request.new(%{"input" => "ok"}, questions, alias_name)
    assert {:ok, response} = Provider.system_one(state, request, [])
    assert response.model == model
    assert response.answers["decision"]["type"] == "noul"
  end

  test "unknown models fail with normalized provider error", %{state: state} do
    assert {:ok, request} =
             Request.new("state", [{"q", %{"type" => "noul"}}], "does-not-exist")

    assert {:error, %SystemOneContracts.Error{type: :model_not_found}} =
             Provider.system_one(state, request, [])
  end
end
