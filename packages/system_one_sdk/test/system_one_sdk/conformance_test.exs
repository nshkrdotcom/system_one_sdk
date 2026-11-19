defmodule SystemOneSDK.ConformanceTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.{Conformance, Error, Test}
  alias SystemOneSDK.Providers.Endpoint

  test "the built-in TypeSafe client provider satisfies SDK conformance offline" do
    client =
      Test.client(model: "jev-test")
      |> Test.stub_sequence([
        {:models,
         [
           %{
             name: "jev-test",
             description: "Synthetic hosted fixture",
             release_date: "2026-09-20"
           }
         ]},
        {:answers,
         [
           noul: {:noul, 0.7},
           route: {:choice, :first, 0.8},
           intensity: {:score, 1.0, 0.9}
         ]}
      ])

    on_exit(fn -> Test.close(client) end)

    assert {:ok, report} = Conformance.run(client)
    assert report.provider == :typesafe
    assert report.model == "jev-test"
    assert report.protocol == SystemOneContracts.protocol()
    assert :ordered_choice in report.checks
    assert Test.verify!(client) == :ok
  end

  test "extraction-only models pass without advertising or receiving decision questions" do
    capabilities = ["question:text", "question:number"]

    client =
      Test.client(provider: Endpoint, model: "extractor-test")
      |> Test.stub_sequence([
        {:models, [%{name: "extractor-test", capabilities: capabilities}]},
        {:response,
         %{
           "model" => "extractor-test",
           "usage" => %{},
           "answers" => %{
             "invoice_id" => %{"type" => "text", "value" => "INV-7"},
             "total" => %{"type" => "number", "value" => 12.50}
           }
         }}
      ])

    assert {:ok, report} = Conformance.run(client, profile: :extraction)
    assert report.capabilities.system_one.capabilities == capabilities
    assert :text in report.checks
    assert :number in report.checks

    assert [_, request] = Test.requests(client)
    assert %{"questions" => fields} = Jason.decode!(request.body)
    assert Enum.sort(Map.keys(fields)) == ["invoice_id", "total"]
    assert :ok = Test.verify!(client)
  end

  test "extraction conformance requires capabilities on the selected model" do
    client =
      Test.client(provider: Endpoint, model: "text-only")
      |> Test.stub_models([
        %{name: "text-only", capabilities: ["question:text"]},
        %{name: "extractor-test", capabilities: ["question:text", "question:number"]}
      ])

    assert {:error,
            %Error{details: %{violation: :provider_capabilities, missing: ["question:number"]}}} =
             Conformance.run(client, profile: :extraction)

    assert [request] = Test.requests(client)
    assert request.method == :get
  end
end
