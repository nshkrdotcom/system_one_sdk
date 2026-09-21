defmodule SystemOneSDK.Providers.Contract do
  @moduledoc """
  Adapter from an inference-side `SystemOneContracts.Provider` into the rich SDK.

  This is the seam used by native providers. The inference provider owns model
  execution; SystemOneSDK continues to own preparation, semantic enrichment,
  batching, telemetry and other client-facing behavior.
  """

  @behaviour SystemOneSDK.Provider

  alias SystemOneContracts.Error, as: ContractError
  alias SystemOneSDK.{ContractBridge, Error}

  defmodule Client do
    @moduledoc false
    @enforce_keys [:inference_provider, :inference_state, :default_model]
    defstruct [:inference_provider, :inference_state, :default_model]
  end

  @impl true
  def id, do: :system_one_contract

  @impl true
  def new_client(opts) when is_list(opts) do
    provider = Keyword.fetch!(opts, :inference_provider)
    ensure_provider!(provider)
    model = required_model!(Keyword.get(opts, :model))

    %Client{
      inference_provider: provider,
      inference_state: Keyword.get(opts, :inference_state),
      default_model: model
    }
  end

  @impl true
  def default_model(%Client{default_model: model}), do: model

  @impl true
  def system_one(%Client{} = client, state, questions, opts) when is_list(opts) do
    execute(client, state, questions, opts)
  end

  @impl true
  def system_one_prepared(%Client{} = client, state, prepared, opts) when is_list(opts) do
    execute(client, state, prepared, opts)
  end

  @impl true
  def list_models(%Client{} = client, opts) when is_list(opts) do
    case client.inference_provider.list_models(client.inference_state, opts) do
      {:ok, response} -> ContractBridge.models_from_contract(response)
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  @impl true
  def capabilities(%Client{} = client) do
    %{
      transport: nil,
      runtime: %{},
      system_one: client.inference_provider.capabilities(client.inference_state),
      assurance: :system_one_provider_contract
    }
  end

  defp execute(client, state, questions, opts) do
    model = Keyword.get(opts, :model) || client.default_model
    extra = normalize_extra(Keyword.get(opts, :extra_body, %{}))

    with {:ok, request} <- ContractBridge.request(state, questions, model, extra),
         {:ok, response} <-
           client.inference_provider.system_one(
             client.inference_state,
             request,
             provider_opts(opts)
           ),
         {:ok, decoded} <- ContractBridge.response_from_contract(response) do
      {:ok, decoded}
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  defp provider_opts(opts), do: Keyword.drop(opts, [:model, :extra_body])

  defp normalize_extra(nil), do: %{}
  defp normalize_extra(extra) when is_map(extra) and not is_struct(extra), do: extra

  defp normalize_extra(other) do
    raise ArgumentError, "extra_body must be a map, got: #{inspect(other)}"
  end

  defp ensure_provider!(provider) when is_atom(provider) do
    required = [id: 0, capabilities: 1, system_one: 3, list_models: 2]

    if Code.ensure_loaded?(provider) and
         Enum.all?(required, fn {name, arity} -> function_exported?(provider, name, arity) end) do
      :ok
    else
      raise Error.configuration("invalid System One inference provider #{inspect(provider)}")
    end
  end

  defp ensure_provider!(provider) do
    raise Error.configuration("invalid System One inference provider #{inspect(provider)}")
  end

  defp required_model!(model) when is_binary(model) do
    case String.trim(model) do
      "" -> raise Error.configuration("model must not be blank")
      value -> value
    end
  end

  defp required_model!(_),
    do: raise(Error.configuration("contract-backed clients require a nonblank :model"))

  defp normalize_error(%Error{} = error), do: error

  defp normalize_error(%ContractError{} = error) do
    %Error{
      type: sdk_error_type(error.type),
      message: error.message,
      path: error.path,
      field_path: if(error.path, do: Enum.join(error.path, ".")),
      cause: error,
      details: error.details
    }
  end

  defp normalize_error(other) do
    %Error{
      type: :api_error,
      message: "System One inference provider failed",
      cause: other,
      details: %{provider: :system_one_contract}
    }
  end

  defp sdk_error_type(:invalid_request), do: :invalid_request
  defp sdk_error_type(:model_not_found), do: :model_not_found
  defp sdk_error_type(:timeout), do: :timeout
  defp sdk_error_type(:cancelled), do: :cancelled
  defp sdk_error_type(:invalid_response), do: :response_validation
  defp sdk_error_type(_), do: :api_error
end
