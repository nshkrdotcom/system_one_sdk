defmodule SystemOneBumblebee do
  @moduledoc """
  Native BEAM/Nx/Bumblebee implementation of the System One inference contract.

  The package owns model registration, immutable artifact verification, native
  adapter loading and long-lived serving state. It deliberately does not own
  HTTP exposure, hosted-provider credentials or service lifecycle management.

  The public System One seam is `SystemOneContracts.Provider`, implemented by
  `SystemOneBumblebee.Provider`.
  """

  alias SystemOneBumblebee.Provider

  @doc "Builds provider state from configured model manifests and a runtime profile."
  @spec new_provider(keyword()) :: {:ok, Provider.State.t()} | {:error, term()}
  def new_provider(opts \\ []), do: Provider.new(opts)
end
