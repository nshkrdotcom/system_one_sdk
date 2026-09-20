defmodule SystemOneSDK.Provider do
  @moduledoc """
  Runtime provider contract for System One execution.

  The semantic SDK owns question preparation, validation, enrichment, batching,
  telemetry, and policy-independent helpers. Providers own execution against a
  concrete System One implementation.
  """

  alias SystemOneSDK.{ListModelsResponse, SystemOneResponse}

  @type provider_client :: term()

  @callback id() :: atom()

  @callback new_client(keyword()) :: provider_client()

  @callback default_model(provider_client()) :: String.t()

  @callback system_one(
              provider_client(),
              term(),
              map(),
              keyword()
            ) ::
              {:ok, SystemOneResponse.t()}
              | {:error, term()}

  @callback list_models(provider_client(), keyword()) ::
              {:ok, ListModelsResponse.t()}
              | {:error, term()}

  @callback capabilities(provider_client()) :: map()
end
