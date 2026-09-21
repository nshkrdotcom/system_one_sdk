defmodule SystemOneBumblebee.ModelAdapter do
  @moduledoc """
  Behaviour implemented by native System One model architectures.

  Adapters receive verified artifact paths and an explicit runtime profile.
  They own architecture-specific preprocessing, graph construction, parameter
  mapping and inference. HTTP and service lifecycle concerns are intentionally
  absent from this contract.
  """

  alias SystemOneBumblebee.{Artifacts, ModelManifest, RuntimeProfile}
  alias SystemOneContracts.V1.{Request, Response}

  @type runtime :: term()

  @callback load(ModelManifest.t(), Artifacts.Prepared.t(), RuntimeProfile.t(), keyword()) ::
              {:ok, runtime()} | {:error, term()}

  @callback infer(runtime(), Request.t(), keyword()) ::
              {:ok, Response.t()} | {:error, term()}

  @callback capabilities(ModelManifest.t()) :: [String.t()]
end
