defmodule SystemOneSDK.ContractBridge do
  @moduledoc false

  alias SystemOneContracts.V1.{Model, ModelsResponse, Request, Response}
  alias SystemOneSDK.{Error, ListModelsResponse, Prepared, SystemOneResponse}

  @spec request(term(), Prepared.t() | map() | list() | struct(), String.t(), map()) ::
          {:ok, Request.t()} | {:error, term()}
  def request(state, %Prepared{} = prepared, model, extra) when is_map(extra) do
    definitions = Prepared.definitions(prepared)

    questions =
      Enum.map(Prepared.wire_keys(prepared), fn key ->
        {key, Map.fetch!(definitions, key).wire}
      end)

    Request.new(state, questions, model, extra: extra)
  end

  def request(state, %Jason.Fragment{} = questions, model, extra) when is_map(extra) do
    with {:ok, json} <- Jason.encode(questions),
         {:ok, decoded} <- Jason.decode(json) do
      Request.new(state, decoded, model, extra: extra)
    else
      {:error, reason} ->
        {:error,
         Error.invalid_request(["questions"], "could not decode prepared question fragment", %{
           cause: reason
         })}
    end
  end

  def request(state, questions, model, extra) when is_map(extra) do
    Request.new(state, questions, model, extra: extra)
  end

  @spec response_from_contract(Response.t()) ::
          {:ok, SystemOneResponse.t()} | {:error, term()}
  def response_from_contract(%Response{} = source) do
    case SystemOneResponse.decode(Response.to_map(source)) do
      {:ok, response} ->
        {:ok,
         %{
           response
           | request_id: source.request_id,
             raw: source.raw || Response.to_map(source)
         }}

      error ->
        error
    end
  rescue
    error ->
      {:error,
       Error.response_contract(:invalid_provider_response, %{
         cause: error
       })}
  end

  def response_from_contract(other) do
    {:error,
     Error.response_contract(:invalid_provider_response, %{
       value: other
     })}
  end

  @spec models_from_contract(ModelsResponse.t()) ::
          {:ok, ListModelsResponse.t()} | {:error, term()}
  def models_from_contract(%ModelsResponse{} = source) do
    body = %{"models" => Enum.map(source.models, &Model.to_map/1)}

    case ListModelsResponse.decode(body) do
      {:ok, response} ->
        {:ok,
         %{
           response
           | request_id: source.request_id,
             raw: source.raw || body
         }}

      error ->
        error
    end
  rescue
    error ->
      {:error,
       Error.response_contract(:invalid_provider_models, %{
         cause: error
       })}
  end

  def models_from_contract(other) do
    {:error,
     Error.response_contract(:invalid_provider_models, %{
       value: other
     })}
  end
end
