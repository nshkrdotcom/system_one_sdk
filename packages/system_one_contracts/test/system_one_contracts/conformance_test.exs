defmodule SystemOneContracts.ConformanceTest do
  use ExUnit.Case, async: true

  alias SystemOneContracts.Conformance
  alias SystemOneContracts.V1.{Model, ModelsResponse, Response, Usage}

  defmodule FakeProvider do
    @behaviour SystemOneContracts.Provider

    @impl true
    def id, do: :fake

    @impl true
    def capabilities(_state) do
      %{
        protocol: SystemOneContracts.protocol(),
        capabilities: SystemOneContracts.Capabilities.core()
      }
    end

    @impl true
    def list_models(_state, _opts), do: {:ok, %ModelsResponse{models: [%Model{name: "fake-model"}]}}

    @impl true
    def system_one(_state, request, _opts) do
      answers =
        Map.new(request.questions, fn
          {key, %{"type" => "noul"}} ->
            {key, %{"type" => "noul", "noul" => 0.5}}

          {key, %{"type" => "choice"}} ->
            {key,
             %{
               "type" => "choice",
               "choice" => "first",
               "confidence" => 0.5,
               "probabilities" => %{"first" => 0.5, "second" => 0.5}
             }}

          {key, %{"type" => "score"}} ->
            {key,
             %{
               "type" => "score",
               "score" => 0.5,
               "confidence" => 0.5,
               "legend" => %{"0" => "low", "1" => "high"},
               "probabilities" => %{"0" => 0.5, "1" => 0.5}
             }}
        end)

      {:ok,
       %Response{
         model: request.model,
         usage: %Usage{},
         answers: answers
       }}
    end
  end

  test "runs reusable inference-provider conformance" do
    assert {:ok, report} = Conformance.run(FakeProvider, :state)
    assert report.provider == :fake
    assert report.model == "fake-model"
    assert :ordered_choice in report.checks
  end
end
