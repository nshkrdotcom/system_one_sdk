defmodule SystemOneSDK.Conformance do
  @moduledoc "Reusable client/provider conformance gate for the rich SystemOneSDK surface."

  alias SystemOneContracts.Capabilities

  alias SystemOneSDK.{
    ChoiceAnswer,
    Client,
    Error,
    ExtractionAnswer,
    ListModelsResponse,
    Models,
    NoulAnswer,
    ScoreAnswer
  }

  @extraction_capabilities ["question:text", "question:number"]

  @doc "Run the decision checks by default, or pass `profile: :extraction` for text and number checks."
  @spec run(Client.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Client{} = client, opts \\ []) when is_list(opts) do
    model = Keyword.get(opts, :model) || client.default_model
    common_opts = Keyword.drop(opts, [:model, :profile])

    case Keyword.get(opts, :profile, :decision) do
      :decision ->
        run_decision(client, model, common_opts)

      :extraction ->
        run_extraction(client, model, common_opts)

      _ ->
        {:error, Error.invalid_request(["options", "profile"], "must be :decision or :extraction")}
    end
  end

  defp run_decision(client, model, opts) do
    questions = [
      noul: SystemOneSDK.noul("Is this fixture affirmative?"),
      route:
        SystemOneSDK.choice(
          "Choose a route.",
          first: "First option",
          second: "Second option"
        ),
      intensity: SystemOneSDK.score("Rate intensity.", ["low", "high"])
    ]

    with {:ok, capabilities} <- semantic_capabilities(client),
         {:ok, %ListModelsResponse{} = catalog} <- SystemOneSDK.list_models(client, opts),
         :ok <- model_present(catalog, model),
         {:ok, response} <-
           SystemOneSDK.evaluate(
             client,
             "System One conformance fixture",
             questions,
             Keyword.put(opts, :model, model)
           ),
         :ok <- answer_shapes(response) do
      {:ok,
       %{
         provider: client.provider.id(),
         model: model,
         protocol: SystemOneContracts.protocol(),
         capabilities: capabilities,
         checks: [
           :capabilities,
           :model_discovery,
           :noul,
           :ordered_choice,
           :score,
           :semantic_enrichment
         ]
       }}
    end
  end

  defp run_extraction(client, model, opts) do
    fields = [
      invoice_id: %{type: "text", instructions: "The invoice ID"},
      total: %{type: "number", instructions: "The invoice total"}
    ]

    with {:ok, capabilities} <- semantic_capabilities(client, []),
         {:ok, %ListModelsResponse{} = catalog} <- SystemOneSDK.list_models(client, opts),
         {:ok, metadata} <- Models.find(catalog, model),
         :ok <- extraction_capabilities(metadata.capabilities),
         {:ok, response} <-
           SystemOneSDK.evaluate(
             client,
             "Invoice INV-7. Total: 12.50.",
             fields,
             Keyword.put(opts, :model, model)
           ),
         :ok <- extraction_values(response) do
      {:ok,
       %{
         provider: client.provider.id(),
         model: model,
         protocol: SystemOneContracts.protocol(),
         capabilities: capabilities,
         model_capabilities: metadata.capabilities,
         checks: [:capabilities, :model_discovery, :text, :number, :semantic_enrichment]
       }}
    end
  end

  defp extraction_capabilities(capabilities) do
    case @extraction_capabilities -- capabilities do
      [] -> :ok
      missing -> {:error, Error.response_contract(:provider_capabilities, %{missing: missing})}
    end
  end

  defp extraction_values(%{
         answers: %{
           invoice_id: %ExtractionAnswer{type: :text, value: "INV-7"},
           total: %ExtractionAnswer{type: :number, value: 12.5}
         }
       }),
       do: :ok

  defp extraction_values(_response),
    do: {:error, Error.response_contract(:conformance_values, %{fields: [:invoice_id, :total]})}

  defp semantic_capabilities(client, required \\ Capabilities.core()) do
    report = Client.capabilities(client)
    semantic = Map.get(report, :system_one) || Map.get(report, "system_one")

    protocol =
      if is_map(semantic),
        do: Map.get(semantic, :protocol) || Map.get(semantic, "protocol"),
        else: nil

    advertised =
      if is_map(semantic),
        do: Map.get(semantic, :capabilities) || Map.get(semantic, "capabilities"),
        else: nil

    with true <- protocol == SystemOneContracts.protocol(),
         {:ok, names} <- Capabilities.normalize(advertised),
         [] <- required -- names do
      {:ok, Map.put(report, :system_one, %{protocol: protocol, capabilities: names})}
    else
      _ ->
        {:error,
         Error.response_contract(:provider_capabilities, %{
           expected_protocol: SystemOneContracts.protocol(),
           required: required,
           actual: semantic
         })}
    end
  end

  defp model_present(%ListModelsResponse{models: models}, model) do
    if Enum.any?(models, &(&1.name == model)),
      do: :ok,
      else: {:error, Error.model_lookup(:model_not_found, model)}
  end

  defp answer_shapes(response) do
    case {
      response.answers[:noul],
      response.answers[:route],
      response.answers[:intensity]
    } do
      {%NoulAnswer{}, %ChoiceAnswer{option_order: [:first, :second]}, %ScoreAnswer{levels: levels}}
      when length(levels) == 2 ->
        :ok

      _ ->
        {:error,
         Error.response_contract(:conformance_shape, %{
           expected: [:noul, :ordered_choice, :score]
         })}
    end
  end
end
