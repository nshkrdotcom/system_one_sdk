defmodule SystemOneSDK.Providers.EndpointTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.{Conformance, Test}
  alias SystemOneSDK.Providers.Endpoint

  test "generic endpoint passes SDK conformance through the isolated Pristine transport" do
    client =
      Test.client(
        provider: Endpoint,
        api_key: "endpoint-test-key",
        base_url: "http://system-one.test.invalid/prefix",
        model: "local-test"
      )
      |> Test.stub_sequence([
        {:models, [%{name: "local-test", capabilities: SystemOneContracts.Capabilities.core()}]},
        {:answers,
         [
           noul: {:noul, 0.8},
           route: {:choice, :first, 0.7},
           intensity: {:score, 1.0, 0.9}
         ]},
        {:answers, [route: {:choice, :z, 0.9}]}
      ])

    on_exit(fn -> Test.close(client) end)

    assert {:ok, report} = Conformance.run(client)
    assert report.provider == :endpoint
    assert report.protocol == SystemOneContracts.protocol()

    assert {:ok, response} =
             SystemOneSDK.evaluate(
               client,
               "strict ordering fixture",
               route: SystemOneSDK.choice("Route?", [z: "Z first", a: "A second"])
             )

    assert response.answers.route.option_order == [:z, :a]

    [models_request, conformance_request, ordering_request] = Test.requests(client)

    for request <- [models_request, conformance_request, ordering_request] do
      headers =
        Map.new(request.headers, fn {key, value} ->
          {String.downcase(to_string(key)), to_string(value)}
        end)

      assert headers["authorization"] == "Bearer endpoint-test-key"
      assert headers["user-agent"] == "system-one-sdk/0.6.0"
    end

    assert URI.parse(models_request.url).path == "/prefix/v1/models"
    assert URI.parse(ordering_request.url).path == "/prefix/v1/systemone"

    body = IO.iodata_to_binary(ordering_request.body)
    {z_at, _} = :binary.match(body, ~s("z":"Z first"))
    {a_at, _} = :binary.match(body, ~s("a":"A second"))
    assert z_at < a_at
    assert Test.verify!(client) == :ok
  end

  test "generic endpoints may omit bearer auth" do
    client =
      Test.client(
        provider: Endpoint,
        api_key: nil,
        base_url: "http://system-one.test.invalid",
        model: "local-test"
      )
      |> Test.stub_models([%{name: "local-test"}])

    on_exit(fn -> Test.close(client) end)

    assert {:ok, _} = SystemOneSDK.list_models(client)
    [request] = Test.requests(client)

    headers =
      Map.new(request.headers, fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value)}
      end)

    refute Map.has_key?(headers, "authorization")
  end
end
