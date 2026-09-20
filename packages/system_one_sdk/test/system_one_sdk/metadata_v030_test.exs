defmodule SystemOneSDK.MetadataV030Test do
  use ExUnit.Case, async: true

  alias SystemOneSDK.{Error, Response, Test}

  test "response metadata exposes stable structural data and prepared fingerprint" do
    client = Test.client() |> Test.stub([q: {:noul, 0.9}], model: "model-a")
    prepared = SystemOneSDK.prepare!(q: SystemOneSDK.noul("Q?"))
    assert {:ok, response} = SystemOneSDK.evaluate(client, "state", prepared)

    metadata = Response.metadata(response)
    assert metadata.model == "model-a"
    assert metadata.prepared_fingerprint == SystemOneSDK.Prepared.fingerprint(prepared)
    assert metadata.retries == 0
    refute Map.has_key?(metadata, :raw)
  end

  test "error metadata is bounded and cancellation-aware" do
    error = %Error{
      type: :request_too_large,
      message: "never surface me as metadata",
      details: %{actual_bytes: 10, max_bytes: 9, request_body: "secret"},
      prepared_fingerprint: "system-one-prepared-v1:abc"
    }

    metadata = Error.metadata(error)
    assert metadata.request_budget == %{actual_bytes: 10, max_bytes: 9}
    assert metadata.prepared_fingerprint == "system-one-prepared-v1:abc"
    refute inspect(metadata) =~ "secret"
    refute Map.has_key?(metadata, :message)
  end
end
