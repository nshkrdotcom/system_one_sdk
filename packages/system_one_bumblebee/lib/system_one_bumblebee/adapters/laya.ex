defmodule SystemOneBumblebee.Adapters.Laya do
  @moduledoc """
  Native Laya model adapter backed by the resident BEAM/Nx runtime.
  """

  @behaviour SystemOneBumblebee.ModelAdapter

  alias SystemOneBumblebee.Models.Laya.Runtime

  @capabilities [
    "question:noul",
    "question:choice",
    "question:score",
    "choice:ordered"
  ]

  @impl true
  def capabilities(_manifest),
    do: @capabilities

  @impl true
  def load(
        manifest,
        artifacts,
        profile,
        opts
      ),
      do:
        Runtime.load(
          manifest,
          artifacts,
          profile,
          opts
        )

  @impl true
  def infer(
        runtime,
        request,
        opts
      ),
      do:
        Runtime.infer(
          runtime,
          request,
          opts
        )
end
