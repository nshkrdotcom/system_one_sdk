defmodule SystemOneContracts.Conformance do
  @moduledoc "Reusable inference-provider conformance checks for `system-one/v1`."

  alias SystemOneContracts.{Capabilities, Error, Provider}
  alias SystemOneContracts.V1.{ModelsResponse, Request, Response}
  alias SystemOneContracts.V1.Validation

  @spec run(module(), Provider.provider_state(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(provider, provider_state, opts \\ []) when is_atom(provider) and is_list(opts) do
    provider_opts = Keyword.drop(opts, [:model])

    with :ok <- provider_module(provider),
         {:ok, capabilities} <- provider_capabilities(provider, provider_state),
         {:ok, catalog} <- list_models(provider, provider_state, provider_opts),
         {:ok, model} <- resolve_model(catalog, Keyword.get(opts, :model)),
         {:ok, request} <- fixture_request(model),
         {:ok, response} <- system_one(provider, provider_state, request, provider_opts),
         :ok <- validate_response(request, response) do
      {:ok,
       %{
         protocol: SystemOneContracts.protocol(),
         provider: provider.id(),
         model: model,
         capabilities: capabilities,
         checks: [:model_discovery, :noul, :ordered_choice, :score, :response_shape]
       }}
    end
  end

  @spec validate_response(Request.t(), Response.t()) :: :ok | {:error, Error.t()}
  def validate_response(%Request{} = request, %Response{} = response) do
    expected = Request.question_keys(request)
    actual = Map.keys(response.answers)

    with :ok <- exact_keys(expected, actual),
         :ok <- answer_types(request, response) do
      :ok
    end
  end

  defp provider_capabilities(provider, provider_state) do
    case provider.capabilities(provider_state) do
      report when is_map(report) -> validate_capabilities(report)
      other -> {:error, Error.invalid_response(["capabilities"], "must be a map", %{value: other})}
    end
  rescue
    error -> {:error, Error.invalid_response(["capabilities"], "provider raised", %{cause: error})}
  end

  defp validate_capabilities(report) do
    protocol = map_value(report, "protocol")
    advertised = map_value(report, "capabilities")

    with :ok <- protocol(protocol),
         {:ok, names} <- normalize_capabilities(advertised),
         :ok <- core_capabilities(names) do
      {:ok, Map.put(report, :capabilities, names)}
    end
  end

  defp protocol(value) do
    expected = SystemOneContracts.protocol()

    if value == expected do
      :ok
    else
      {:error,
       Error.invalid_response(["capabilities", "protocol"], "does not match system-one/v1", %{
         actual: value,
         expected: expected
       })}
    end
  end

  defp normalize_capabilities(values) do
    case Capabilities.normalize(values) do
      {:ok, names} ->
        {:ok, names}

      {:error, _} ->
        {:error, Error.invalid_response(["capabilities"], "must contain capability names")}
    end
  end

  defp core_capabilities(names) do
    missing = Capabilities.core() -- names

    if missing == [] do
      :ok
    else
      {:error,
       Error.invalid_response(["capabilities"], "missing core System One capabilities", %{
         missing: missing
       })}
    end
  end

  defp list_models(provider, provider_state, opts) do
    case provider.list_models(provider_state, opts) do
      {:ok, %ModelsResponse{} = catalog} ->
        normalize_catalog(catalog)

      {:ok, other} ->
        {:error,
         Error.invalid_response(["models"], "provider returned the wrong type", %{value: other})}

      {:error, _} = error ->
        error

      other ->
        {:error,
         Error.invalid_response(["models"], "provider returned an invalid result", %{value: other})}
    end
  rescue
    error -> {:error, Error.invalid_response(["models"], "provider raised", %{cause: error})}
  end

  defp normalize_catalog(catalog) do
    catalog
    |> ModelsResponse.to_map()
    |> ModelsResponse.decode()
  rescue
    error ->
      {:error,
       Error.invalid_response(["models"], "provider returned invalid model metadata", %{
         cause: error
       })}
  end

  defp system_one(provider, provider_state, request, opts) do
    case provider.system_one(provider_state, request, opts) do
      {:ok, %Response{} = response} ->
        normalize_response(response)

      {:ok, other} ->
        {:error,
         Error.invalid_response([], "provider returned the wrong response type", %{value: other})}

      {:error, _} = error ->
        error

      other ->
        {:error, Error.invalid_response([], "provider returned an invalid result", %{value: other})}
    end
  rescue
    error -> {:error, Error.invalid_response([], "provider raised", %{cause: error})}
  end

  defp normalize_response(response) do
    response
    |> Response.to_map()
    |> Response.decode()
  rescue
    error ->
      {:error, Error.invalid_response([], "provider returned an invalid response", %{cause: error})}
  end

  defp fixture_request(model) do
    questions = [
      {"noul", %{"type" => "noul", "instructions" => "Is this statement affirmative?"}},
      {"choice",
       %{
         "type" => "choice",
         "instructions" => "Choose the better label.",
         "criteria" =>
           Jason.OrderedObject.new([
             {"first", "First option"},
             {"second", "Second option"}
           ])
       }},
      {"score",
       %{
         "type" => "score",
         "instructions" => "Rate the intensity.",
         "criteria" => ["low", "high"]
       }}
    ]

    Request.new("System One provider conformance fixture", questions, model)
  end

  defp provider_module(provider) do
    required = [id: 0, capabilities: 1, system_one: 3, list_models: 2]

    if Code.ensure_loaded?(provider) and
         Enum.all?(required, fn {name, arity} -> function_exported?(provider, name, arity) end) do
      :ok
    else
      {:error,
       Error.invalid_request(["provider"], "does not implement SystemOneContracts.Provider")}
    end
  end

  defp resolve_model(%ModelsResponse{models: models}, nil) do
    case models do
      [%{name: name} | _] -> {:ok, name}
      [] -> {:error, Error.invalid_response(["models"], "provider returned an empty catalog")}
    end
  end

  defp resolve_model(%ModelsResponse{models: models}, requested) when is_binary(requested) do
    case Validation.nonblank_string(requested, ["model"]) do
      {:ok, model} ->
        if Enum.any?(models, &(&1.name == model)) do
          {:ok, model}
        else
          {:error,
           %Error{
             type: :model_not_found,
             message: "Conformance model not found",
             details: %{model: model}
           }}
        end

      :error ->
        {:error, Error.invalid_request(["model"], "must be nonblank")}
    end
  end

  defp resolve_model(_catalog, _requested),
    do: {:error, Error.invalid_request(["model"], "must be a string")}

  defp exact_keys(expected, actual) do
    if MapSet.new(expected) == MapSet.new(actual) do
      :ok
    else
      {:error,
       Error.invalid_response(["answers"], "answer keys do not match requested questions", %{
         expected: expected,
         actual: actual
       })}
    end
  end

  defp answer_types(%Request{questions: questions}, %Response{answers: answers}) do
    Enum.reduce_while(questions, :ok, fn {key, question}, :ok ->
      expected = Validation.value(question, "type")
      actual = answers |> Map.fetch!(key) |> Validation.value("type")

      if expected == actual do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Error.invalid_response(["answers", key, "type"], "does not match question type", %{
            expected: expected,
            actual: actual
          })}}
      end
    end)
  end

  defp map_value(map, "protocol"), do: Map.get(map, "protocol") || Map.get(map, :protocol)

  defp map_value(map, "capabilities"),
    do: Map.get(map, "capabilities") || Map.get(map, :capabilities)
end
