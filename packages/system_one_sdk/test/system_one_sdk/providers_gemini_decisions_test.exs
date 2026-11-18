defmodule SystemOneSDK.Providers.GeminiDecisionsTest do
  use ExUnit.Case, async: true

  alias SystemOneSDK.{Error, Prepared, RetryPolicy, Test}
  alias SystemOneSDK.Providers.GeminiDecisions

  test "evaluates unified and native Gemini Decisions via SystemOneSDK.Test transport" do
    uni_client =
      Test.client(
        provider: GeminiDecisions,
        decisions_mode: :unified,
        api_key: "uni-test-key",
        base_url: "http://decisions.test.invalid",
        model: "gemini-decision-1"
      )
      |> Test.stub_sequence([
        {:callback,
         fn req ->
           assert URI.parse(req.url).path == "/v1/decisions"
           headers = downcase_headers(req.headers)
           assert headers["authorization"] == "Bearer uni-test-key"
           body = req.body |> IO.iodata_to_binary() |> Jason.decode!()
           assert body["model"] == "gemini-decision-1"
           assert is_binary(body["input"])
           assert [%{"type" => "predicate", "name" => "is_spam"}] = body["questions"]

           {:response, %{"answers" => [%{"name" => "is_spam", "probability" => 0.91}]},
            headers: %{"x-request-id" => "req-uni-1"}}
         end}
      ])

    nat_client =
      Test.client(
        provider: GeminiDecisions,
        decisions_mode: :native,
        api_key: "nat-test-key",
        base_url: "http://decisions.test.invalid",
        model: "gemini-decision-2"
      )
      |> Test.stub_sequence([
        {:callback,
         fn req ->
           assert URI.parse(req.url).path == "/v1beta/decisions"
           headers = downcase_headers(req.headers)
           assert headers["x-goog-api-key"] == "nat-test-key"
           refute Map.has_key?(headers, "authorization")
           body = req.body |> IO.iodata_to_binary() |> Jason.decode!()
           assert body["model"] == "gemini-decision-2"
           assert %{"is_spam" => %{"type" => "noul"}} = body["questions"]

           {:response, %{"answers" => %{"is_spam" => %{"noul" => 0.14}}},
            headers: %{"x-request-id" => "req-nat-1"}}
         end}
      ])

    on_exit(fn ->
      Test.close(uni_client)
      Test.close(nat_client)
    end)

    questions = [is_spam: SystemOneSDK.noul("Is this spam?")]

    assert {:ok, uni_resp} = SystemOneSDK.evaluate(uni_client, %{"body" => "win cash"}, questions)
    assert uni_resp.answers.is_spam.noul == 0.91
    assert uni_resp.request_id == "req-uni-1"
    assert %Pristine.Response{} = uni_resp.raw_http_response

    assert {:ok, nat_resp} =
             SystemOneSDK.evaluate(nat_client, %{"body" => "meeting notes"}, questions)

    assert nat_resp.answers.is_spam.noul == 0.14
    assert nat_resp.request_id == "req-nat-1"
    assert Test.verify!(uni_client) == :ok
    assert Test.verify!(nat_client) == :ok
  end

  test "normalizes Pristine HTTP and transport errors into SystemOneSDK.Error" do
    client =
      Test.client(
        provider: GeminiDecisions,
        decisions_mode: :unified,
        api_key: "uni-test-key",
        base_url: "http://decisions.test.invalid"
      )
      |> Test.stub_sequence([
        {:http_error, 401, body: %{"error" => %{"message" => "Invalid key"}}},
        {:transport_error, :timeout}
      ])

    on_exit(fn -> Test.close(client) end)

    questions = [is_spam: SystemOneSDK.noul("Is this spam?")]

    assert {:error, %Error{type: :authentication, status: 401}} =
             SystemOneSDK.evaluate(client, %{"body" => "a"}, questions)

    assert {:error, %Error{type: :timeout}} =
             SystemOneSDK.evaluate(client, %{"body" => "b"}, questions)

    assert Test.verify!(client) == :ok
  end

  test "supports auth_mode: :none, case-insensitive extra_headers, and per-call model override" do
    client =
      Test.client(
        provider: GeminiDecisions,
        decisions_mode: :unified,
        auth_mode: :none,
        api_key: "ignored-key",
        base_url: "https://decisions.test.invalid"
      )
      |> Test.stub_sequence([
        {:callback,
         fn req ->
           headers = downcase_headers(req.headers)
           refute Map.has_key?(headers, "authorization")
           refute Map.has_key?(headers, "x-goog-api-key")
           assert headers["x-num"] == "42"
           body = req.body |> IO.iodata_to_binary() |> Jason.decode!()
           assert body["model"] == "gemini-decision-override"
           {:response, %{"answers" => [%{"name" => "is_spam", "probability" => 0.12}]}}
         end}
      ])

    on_exit(fn -> Test.close(client) end)

    prep = Prepared.new!(is_spam: SystemOneSDK.noul("Is this spam?"))

    assert {:ok, resp} =
             GeminiDecisions.system_one_prepared(
               client.provider_client,
               %{a: 1},
               prep,
               model: "gemini-decision-override",
               extra_headers: %{"X-Num" => 42}
             )

    assert resp.answers["is_spam"].noul == 0.12
    assert Test.verify!(client) == :ok
  end

  test "aligns :timeout (seconds) and :timeout_ms (ms) and validates per-call options" do
    c_sec =
      GeminiDecisions.new_client(
        base_url: "http://decisions.test.invalid",
        timeout: 2.5
      )

    c_ms =
      GeminiDecisions.new_client(
        base_url: "http://decisions.test.invalid",
        timeout_ms: 2_500
      )

    assert c_sec.timeout_ms == 2_500
    assert c_ms.timeout_ms == 2_500

    assert_raise Error, ~r/timeout/, fn ->
      GeminiDecisions.new_client(base_url: "http://decisions.test.invalid", timeout: 0)
    end

    assert_raise Error, ~r/timeout_ms/, fn ->
      GeminiDecisions.new_client(base_url: "http://decisions.test.invalid", timeout_ms: -5)
    end

    client =
      Test.client(
        provider: GeminiDecisions,
        decisions_mode: :unified,
        api_key: "key",
        base_url: "http://decisions.test.invalid",
        timeout: 5
      )
      |> Test.stub_sequence([
        {:callback,
         fn _req ->
           {:response, %{"answers" => [%{"name" => "is_spam", "probability" => 0.5}]}}
         end},
        {:callback,
         fn _req ->
           {:response, %{"answers" => [%{"name" => "is_spam", "probability" => 0.6}]}}
         end}
      ])

    on_exit(fn -> Test.close(client) end)

    assert client.timeout_ms == 5_000
    prep = Prepared.new!(is_spam: SystemOneSDK.noul("Is this spam?"))

    assert {:ok, _} =
             GeminiDecisions.system_one_prepared(
               client.provider_client,
               %{a: 1},
               prep,
               timeout: 1.5
             )

    assert {:ok, _} =
             GeminiDecisions.system_one_prepared(
               client.provider_client,
               %{a: 2},
               prep,
               timeout_ms: 1_500
             )

    for bad_opts <- [
          [timeout: -1],
          [timeout: 0.0001],
          [timeout_ms: 0],
          [retry: :invalid],
          [extra_headers: [:malformed]],
          [extra_headers: %{"X-Bad" => %{nested: true}}],
          [model: "   "]
        ] do
      assert {:error, %Error{type: :configuration}} =
               GeminiDecisions.system_one_prepared(client.provider_client, %{a: 3}, prep, bad_opts)
    end

    assert {:error, %Error{type: :invalid_request}} =
             GeminiDecisions.system_one_prepared(
               client.provider_client,
               %{a: 4},
               prep,
               extra_body: [:not_a_map]
             )

    assert Test.verify!(client) == :ok
  end

  test "strips /v1/decisions and /v1beta/decisions suffixes without duplicating paths" do
    assert GeminiDecisions.resolve_decisions_path([], :unified, "http://host:4000") ==
             "/v1/decisions"

    assert GeminiDecisions.resolve_decisions_path([], :unified, "http://host:4000/v1") ==
             "/decisions"

    assert GeminiDecisions.resolve_decisions_path([], :unified, "http://host:4000/v1/") ==
             "/decisions"

    assert GeminiDecisions.resolve_decisions_path(
             [],
             :unified,
             "http://host:4000/v1/decisions"
           ) == ""

    assert GeminiDecisions.resolve_decisions_path(
             [],
             :native,
             "https://generativelanguage.googleapis.com"
           ) == "/v1beta/decisions"

    assert GeminiDecisions.resolve_decisions_path(
             [],
             :native,
             "https://generativelanguage.googleapis.com/v1beta"
           ) == "/decisions"

    assert GeminiDecisions.resolve_decisions_path(
             [],
             :native,
             "https://generativelanguage.googleapis.com/v1beta/decisions"
           ) == ""

    assert GeminiDecisions.resolve_decisions_path(
             [decisions_path: "/gemini/v1beta/decisions"],
             :native,
             "http://host:4000"
           ) == "/gemini/v1beta/decisions"

    client =
      Test.client(
        provider: GeminiDecisions,
        decisions_mode: :unified,
        api_key: "key",
        base_url: "http://host:4000/v1/decisions"
      )
      |> Test.stub_sequence([
        {:callback,
         fn req ->
           assert req.url == "http://host:4000/v1/decisions"
           {:response, %{"answers" => [%{"name" => "is_spam", "probability" => 0.1}]}}
         end}
      ])

    on_exit(fn -> Test.close(client) end)

    assert client.base_url == "http://host:4000"
    assert client.provider_client.decisions_path == "/v1/decisions"

    prep = Prepared.new!(is_spam: SystemOneSDK.noul("Is this spam?"))
    assert {:ok, _} = GeminiDecisions.system_one_prepared(client.provider_client, %{a: 1}, prep, [])

    native_client =
      GeminiDecisions.new_client(
        decisions_mode: :native,
        base_url: "http://host:4000/gemini/v1beta/decisions/"
      )

    assert native_client.base_url == "http://host:4000/gemini"
    assert native_client.decisions_path == "/v1beta/decisions"
    assert Test.verify!(client) == :ok
  end

  test "invokes secret resolvers once and merges Accept case-insensitively" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

    key_resolver = fn ->
      Agent.update(counter, &(&1 + 1))
      "resolved-key"
    end

    url_resolver = fn ->
      Agent.update(counter, &(&1 + 1))
      "http://host:4000"
    end

    client =
      GeminiDecisions.new_client(
        decisions_mode: :unified,
        auth_mode: :none,
        api_key: key_resolver,
        base_url: url_resolver,
        headers: %{"accept" => "application/vnd.custom+json"}
      )

    assert Agent.get(counter, & &1) == 2
    assert Map.get(client.context.headers, "accept") == "application/vnd.custom+json"
    refute Map.has_key?(client.context.headers, "Accept")

    for invalid_secret <- Jason.decode!(~s([123, {"invalid": "secret"}])) do
      assert_raise Error, ~r/Invalid secret or URL/, fn ->
        GeminiDecisions.resolve_secret(invalid_secret)
      end
    end
  end

  test "supports default RetryPolicy, headers: nil, capabilities/1, and list_models/2" do
    client =
      SystemOneSDK.new_client(
        provider: GeminiDecisions,
        base_url: "http://localhost:4000",
        headers: nil
      )

    assert client.provider == GeminiDecisions
    assert client.provider_client.headers == %{}
    assert %RetryPolicy{max_retries: 2} = client.retry

    refute function_exported?(GeminiDecisions, :from_response, 4)
    refute function_exported?(GeminiDecisions, :validation_error, 3)
    refute function_exported?(GeminiDecisions, :connection_error, 2)

    assert {:ok, %SystemOneSDK.ListModelsResponse{models: []}} = SystemOneSDK.list_models(client)
    caps = SystemOneSDK.Client.capabilities(client)
    assert caps.provider == :gemini_decisions
    assert caps.decisions_mode == :unified
    assert caps.auth_mode == :bearer
  end

  test "validates :model in new_client/1 and resolve_call_model/2 and rejects nil header values" do
    for bad_model <- ["", "   ", 123, false] do
      assert_raise Error, fn ->
        GeminiDecisions.new_client(
          base_url: "http://decisions.test.invalid",
          model: bad_model
        )
      end
    end

    assert_raise Error, ~r/headers/, fn ->
      GeminiDecisions.new_client(
        base_url: "http://decisions.test.invalid",
        headers: [{"x-request-id", nil}]
      )
    end

    client =
      GeminiDecisions.new_client(
        base_url: "http://decisions.test.invalid",
        api_key: "key"
      )

    prep = Prepared.new!(is_spam: SystemOneSDK.noul("Is this spam?"))

    assert {:error, %Error{type: :configuration}} =
             GeminiDecisions.system_one_prepared(
               client,
               %{a: 1},
               prep,
               extra_headers: %{"x-request-id" => nil}
             )

    for invalid_default <- ["", "   ", 123, nil] do
      broken_client = %{client | default_model: invalid_default}

      assert {:error, %Error{type: :configuration}} =
               GeminiDecisions.system_one_prepared(broken_client, %{a: 1}, prep, [])
    end
  end

  defp downcase_headers(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end
end
