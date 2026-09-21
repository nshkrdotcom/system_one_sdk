defmodule SystemOneContracts.Error do
  @moduledoc "Normalized inference-provider errors shared across System One implementations."

  @type error_type ::
          :invalid_request
          | :unsupported
          | :model_not_found
          | :overloaded
          | :timeout
          | :cancelled
          | :provider_unavailable
          | :invalid_response
          | :internal

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          path: [String.t()] | nil,
          details: map(),
          cause: term()
        }

  defexception type: :internal,
               message: "System One provider error",
               path: nil,
               details: %{},
               cause: nil

  @spec invalid_request([String.t()], String.t(), map()) :: t()
  def invalid_request(path, reason, details \\ %{}) when is_list(path) and is_binary(reason) do
    %__MODULE__{
      type: :invalid_request,
      message: "Invalid System One request at #{inspect(path)}: #{reason}",
      path: path,
      details: Map.put(details, :reason, reason)
    }
  end

  @spec invalid_response([String.t()], String.t(), map()) :: t()
  def invalid_response(path, reason, details \\ %{}) when is_list(path) and is_binary(reason) do
    %__MODULE__{
      type: :invalid_response,
      message: "Invalid System One response at #{inspect(path)}: #{reason}",
      path: path,
      details: Map.put(details, :reason, reason)
    }
  end
end
