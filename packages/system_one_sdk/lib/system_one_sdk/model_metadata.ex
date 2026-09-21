defmodule SystemOneSDK.ModelMetadata do
  @moduledoc "Provider-neutral metadata for one System One model."

  @enforce_keys [:name]
  defstruct [:name, :description, :release_date, capabilities: [], metadata: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          release_date: String.t() | nil,
          capabilities: [String.t()],
          metadata: map()
        }
end
