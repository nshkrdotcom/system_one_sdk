defmodule SystemOneSDK.Providers.ContractTest do
  use ExUnit.Case, async: true

  alias SystemOneContracts.V1.{Model, ModelsResponse, Request, Response, Usage}
  alias SystemOneSDK.{Client, RuntimeCapabilities}
  alias SystemOneSDK.Providers.Contract

  defmodule FakeInference do
    @behaviour SystemOneContracts.Provider

    @impl true
    def id, do: :fake_native

    @impl true
    def capabilities(_owner) do
      %{
        protocol: SystemOneContracts.protocol(),
        capabilities: SystemOneContracts.Capabilities.core()
      }
    end

    @impl true
    def list_models(owner, _opts) do
      send(owner, :list_models)
      {:ok, %ModelsResponse{models: [%Model{name: "native-test"}]}}
    end

    @impl true
    def system_one(owner, %Request{} = request, _opts) do
      send(owner, {:request, request})

      answers =
        Map.new(request.questions, fn
          {key, %{"type" => "noul"}} ->
            {key, %{"type" => "noul", "noul" => 0.75}}

          {key, %{"type" => "choice"}} ->
            {key,
             %{
               "type" => "choice",
               "choice" => "z",
               "confidence" => 0.8,
               "probabilities" => %{"z" => 0.8, "a" => 0.2}
             }}

          {key, %{"type" => "score"}} ->
            {key,
             %{
               "type" => "score",
               "score" => 1.0,
               "confidence" => 0.9,
               "legend" => %{"0" => "low", "1" => "high"},
               "probabilities" => %{"0" => 0.0, "1" => 1.0}
             }}
        end)

      {:ok,
       %Response{
         model: request.model,
         usage: %Usage{input_tokens: 4, output_tokens: 1},
         answers: answers,
         request_id: "req-native-test"
       }}
    end
  end

  test "bridges an inference provider without making it depend on the rich SDK" do
    client =
      Client.new(
        provider: Contract,
        provider_opts: [
          inference_provider: FakeInference,
          inference_state: self(),
          model: "native-test"
        ]
      )

    questions = [
      signal: SystemOneSDK.noul("Signal?"),
      route: SystemOneSDK.choice("Route?", [z: "Z first", a: "A second"]),
      intensity: SystemOneSDK.score("Intensity?", ["low", "high"])
    ]

    assert {:ok, response} = SystemOneSDK.evaluate(client, %{"x" => 1}, questions)
    assert response.model == "native-test"
    assert response.request_id == "req-native-test"
    assert response.answers.signal.noul == 0.75
    assert response.answers.route.choice == :z
    assert response.answers.route.option_order == [:z, :a]
    assert response.answers.intensity.levels == [{"low", 0.0}, {"high", 1.0}]

    assert_receive {:request, %Request{} = request}
    assert Request.question_keys(request) == ["signal", "route", "intensity"]

    route = request.questions |> Enum.into(%{}) |> Map.fetch!("route")
    route_json = Jason.encode!(route)
    {z_at, _} = :binary.match(route_json, ~s("z":"Z first"))
    {a_at, _} = :binary.match(route_json, ~s("a":"A second"))
    assert z_at < a_at

    assert {:ok, models} = SystemOneSDK.list_models(client)
    assert_receive :list_models
    assert [%SystemOneSDK.ModelMetadata{name: "native-test"}] = models.models

    capabilities = RuntimeCapabilities.report(client)
    assert capabilities.system_one.protocol == SystemOneContracts.protocol()
    assert capabilities.runtime.unary_cancellation == %{status: :unverified}
  end
end
