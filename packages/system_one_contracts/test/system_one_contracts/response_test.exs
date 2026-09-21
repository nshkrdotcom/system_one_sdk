defmodule SystemOneContracts.ResponseTest do
  use ExUnit.Case, async: true

  alias SystemOneContracts.V1.{Model, ModelsResponse, Response}

  test "decodes canonical answers and preserves future answer types" do
    body = %{
      "model" => "model-a",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 2},
      "answers" => %{
        "yes" => %{"type" => "noul", "noul" => 0.9},
        "pick" => %{
          "type" => "choice",
          "choice" => "a",
          "confidence" => 0.7,
          "probabilities" => %{"a" => 0.7, "b" => 0.3}
        },
        "future" => %{"type" => "future-answer", "payload" => %{"x" => 1}}
      }
    }

    assert {:ok, %Response{} = response} = Response.decode(body)
    assert response.answers["future"]["payload"] == %{"x" => 1}
  end

  test "model metadata requires only a stable name" do
    assert {:ok, %Model{name: "local-model", description: nil}} =
             Model.decode(%{"name" => "local-model"})

    assert {:ok, %ModelsResponse{models: [%Model{name: "local-model"}]}} =
             ModelsResponse.decode(%{"models" => [%{"name" => "local-model"}]})
  end
end
