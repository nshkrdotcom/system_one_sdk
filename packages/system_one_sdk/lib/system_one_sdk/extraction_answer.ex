defmodule SystemOneSDK.ExtractionAnswer do
  @moduledoc """
  A typed text or numeric value extracted by a System One provider.

  `value` is `nil` when the provider returned an explicit null. `span` holds the
  provider's source offsets, when supplied. Offset units and the source they
  refer to are defined by the provider. Some providers supply a candidate span
  even when the value is null. `confidence` and `null_probability` are optional.
  The original answer is available in `raw`.
  """

  @enforce_keys [:type, :value]
  defstruct [:type, :value, :span, :confidence, :null_probability, :id, :raw]

  @type t :: %__MODULE__{
          type: :text | :number,
          value: String.t() | number() | nil,
          span: {non_neg_integer(), non_neg_integer()} | nil,
          confidence: number() | nil,
          null_probability: number() | nil,
          id: atom() | String.t() | nil,
          raw: map() | nil
        }
end
