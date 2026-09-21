defmodule SystemOneContracts.Provider do
  @moduledoc """
  Inference-side System One provider behaviour.

  Client construction, HTTP transport, authentication, retry policy and service
  lifecycle intentionally live outside this behaviour. `provider_state` is opaque
  implementation state supplied by the caller that owns those concerns.
  """

  alias SystemOneContracts.V1.{ModelsResponse, Request, Response}

  @type provider_state :: term()

  @callback id() :: atom() | String.t()
  @callback capabilities(provider_state()) :: map()
  @callback system_one(provider_state(), Request.t(), keyword()) ::
              {:ok, Response.t()} | {:error, term()}
  @callback list_models(provider_state(), keyword()) ::
              {:ok, ModelsResponse.t()} | {:error, term()}
end
