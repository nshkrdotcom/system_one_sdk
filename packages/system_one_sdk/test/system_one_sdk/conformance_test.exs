defmodule SystemOneSDK.ConformanceTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.{Conformance, Test}

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
end
