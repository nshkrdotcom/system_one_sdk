defmodule SystemOneSDK.Conformance do
  @moduledoc "Reusable client/provider conformance gate for the rich SystemOneSDK surface."

  alias SystemOneContracts.Capabilities
  alias SystemOneSDK.{ChoiceAnswer, Client, ListModelsResponse, NoulAnswer, ScoreAnswer}

  @spec run(Client.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Client{} = client, opts \\ []) when is_list(opts) do
    model = Keyword.get(opts, :model) || client.default_model
    common_opts = Keyword.drop(opts, [:model])
    request_opts = Keyword.put(common_opts, :model, model)

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
         {:ok, %ListModelsResponse{} = catalog} <- SystemOneSDK.list_models(client, common_opts),
         :ok <- model_present(catalog, model),
         {:ok, response} <-
           SystemOneSDK.evaluate(client, "System One conformance fixture", questions, request_opts),
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

  defp semantic_capabilities(client) do
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
         [] <- Capabilities.core() -- names do
      {:ok, Map.put(report, :system_one, %{protocol: protocol, capabilities: names})}
    else
      _ ->
        {:error,
         SystemOneSDK.Error.response_contract(:provider_capabilities, %{
           expected_protocol: SystemOneContracts.protocol(),
           required: Capabilities.core(),
           actual: semantic
         })}
    end
  end

  defp model_present(%ListModelsResponse{models: models}, model) do
    if Enum.any?(models, &(&1.name == model)),
      do: :ok,
      else: {:error, SystemOneSDK.Error.model_lookup(:model_not_found, model)}
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
         SystemOneSDK.Error.response_contract(:conformance_shape, %{
           expected: [:noul, :ordered_choice, :score]
         })}
    end
  end
end
