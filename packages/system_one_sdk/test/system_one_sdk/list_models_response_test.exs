defmodule SystemOneSDK.ListModelsResponseTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.ListModelsResponse

  test "decodes provider-neutral models and ignores unknown fields" do
    body = %{
      "models" => [
        %{
          "name" => "jev-latest",
          "description" => "Jev",
          "release_date" => "2026-09-01",
          "capabilities" => ["question:noul", "question:choice"],
          "metadata" => %{"family" => "jev"},
          "future_field" => 123
        }
      ]
    }

    assert {:ok, %ListModelsResponse{models: [model]}} = ListModelsResponse.decode(body)
    assert model.name == "jev-latest"
    assert model.description == "Jev"
    assert model.release_date == "2026-09-01"
    assert model.capabilities == ["question:noul", "question:choice"]
    assert model.metadata == %{"family" => "jev"}
  end

  test "minimal model metadata requires only a stable name" do
    assert {:ok, %ListModelsResponse{models: [model]}} =
             ListModelsResponse.decode(%{"models" => [%{"name" => "local-model"}]})

    assert model.name == "local-model"
    assert model.description == nil
    assert model.release_date == nil
    assert model.capabilities == []
    assert model.metadata == %{}
  end

  test "attaches HTTP metadata when an optional model field is malformed" do
    body = %{"models" => [%{"name" => "test", "capabilities" => [123]}]}

    raw = %Pristine.Response{
      status: 200,
      headers: %{"x-typesafe-request-id" => "req-models"},
      body: Jason.encode!(body),
      metadata: %{method: :get, url: "https://api.typesafe.ai/v1/models"}
    }

    wrapped = %SystemOneSDK.TransportResponse{
      data: body,
      raw_http_response: raw,
      request_id: "req-models"
    }

    assert {:error, %SystemOneSDK.Error{} = error} = ListModelsResponse.decode(wrapped)
    assert error.status == 200
    assert error.request_id == "req-models"
    assert error.field_path == "models[0].capabilities"
    assert error.body == body
    assert error.raw_http_response == raw
  end
end
