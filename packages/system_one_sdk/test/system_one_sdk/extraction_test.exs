defmodule SystemOneSDK.ExtractionTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.{Error, ExtractionAnswer, Response, SystemOneResponse, Test}
  alias SystemOneSDK.Providers.Endpoint

  @state "Invoice INV-7. Total: $0.00."

  test "evaluate returns typed extraction through a v1 endpoint and preserves caller keys" do
    invoice_id = %{
      "type" => "text",
      "value" => "INV-7",
      "span" => [8, 13],
      "confidence" => 0.99,
      "p_null" => 0,
      "complete" => true
    }

    client =
      Test.client(provider: Endpoint, model: "extractor-test")
      |> Test.stub_response(
        response(%{
          "invoice_id" => invoice_id,
          "total" => %{"type" => "number", "value" => 0},
          "po_number" => %{"type" => "text", "value" => nil, "p_null" => 1}
        })
      )

    fields =
      SystemOneSDK.prepare!([
        {:invoice_id, %{type: "text"}},
        {:total, %{type: "number", decimals: 2}},
        {"po_number", %{type: "text", instructions: "Purchase order number"}}
      ])

    assert {:ok, result} = SystemOneSDK.evaluate(client, @state, fields)
    assert Response.values(result) == %{:invoice_id => "INV-7", :total => 0, "po_number" => nil}

    assert %ExtractionAnswer{
             id: :invoice_id,
             type: :text,
             span: {8, 13},
             confidence: 0.99,
             null_probability: 0,
             raw: ^invoice_id
           } = Response.fetch!(result, :invoice_id)

    assert %ExtractionAnswer{type: :number, value: 0, confidence: nil} = result.answers.total
    assert %ExtractionAnswer{value: nil, null_probability: 1} = result.answers["po_number"]
    assert result.unknown_answers == %{}

    assert [request] = Test.requests(client)
    assert URI.parse(request.url).path == "/v1/systemone"

    assert %{"questions" => %{"total" => %{"type" => "number", "decimals" => 2}}} =
             Jason.decode!(request.body)
  end

  test "requested extraction rejects malformed values and provider-reported failures" do
    client = Test.client(provider: Endpoint, model: "extractor-test")

    for {type, attributes, key} <- [
          {"text", %{}, "value"},
          {"text", %{"value" => false}, "value"},
          {"number", %{"value" => "12.50"}, "value"},
          {"text", %{"value" => "INV-7", "span" => [13, 8]}, "span"},
          {"number", %{"value" => 0, "confidence" => false}, "confidence"},
          {"number", %{"value" => 0, "p_null" => 1.1}, "p_null"},
          {"text", %{"value" => nil, "valid" => false}, "valid"},
          {"text", %{"value" => nil, "complete" => false}, "complete"},
          {"text", %{"value" => nil, "complete" => "false"}, "complete"}
        ] do
      Test.stub_response(client, response(%{field: Map.put(attributes, "type", type)}))

      assert {:error, %Error{type: :response_validation, path: ["answers", "field", ^key]}} =
               SystemOneSDK.evaluate(client, @state, field: %{type: type})
    end
  end

  test "wire decoding and decision evaluation preserve unrequested extraction-shaped entries" do
    client = Test.client(provider: Endpoint, model: "extractor-test")
    extra = %{"type" => "text", "payload" => "extension with its own shape"}
    body = response(%{"decision" => %{"type" => "noul", "noul" => 0.75}, "extra" => extra})
    Test.stub_response(client, body)

    assert {:ok, %{unknown_answers: %{"extra" => ^extra}}} = SystemOneResponse.decode(body)

    assert {:ok, result} =
             SystemOneSDK.evaluate(client, @state, decision: SystemOneSDK.noul("An invoice?"))

    assert Response.values(result) == %{decision: 0.75}
    assert result.unknown_answers == %{"extra" => extra}
  end

  @tag :capture_log
  test "evaluate rejects omitted fields and mismatched tags for extraction questions" do
    client = Test.client(provider: Endpoint, model: "extractor-test")

    for {answers, path} <- [
          {%{}, ["answers", "total"]},
          {%{total: %{type: "text", value: "zero"}}, ["answers", "total", "type"]},
          {%{total: %{type: "future", value: 0}}, ["answers", "total", "type"]}
        ] do
      Test.stub_response(client, response(answers))

      assert {:error, %Error{type: :response_validation, path: ^path}} =
               SystemOneSDK.evaluate(client, @state, total: %{type: "number"})
    end
  end

  defp response(answers), do: %{"model" => "extractor-test", "usage" => %{}, "answers" => answers}
end
