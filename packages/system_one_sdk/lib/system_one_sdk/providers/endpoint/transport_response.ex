defmodule SystemOneSDK.Providers.Endpoint.TransportResponse do
  @moduledoc false

  @enforce_keys [:data, :raw_http_response]
  defstruct [
    :data,
    :raw_http_response,
    :request_id,
    :method,
    :url,
    retries: 0,
    elapsed_ms: 0
  ]

  def new(%Pristine.Core.Response{} = response, opts) when is_list(opts) do
    raw = Pristine.Response.from_transport(response)

    %__MODULE__{
      data: Keyword.fetch!(opts, :data),
      raw_http_response: raw,
      request_id: request_id(response.headers),
      method: Keyword.get(opts, :method),
      url: Keyword.get(opts, :url),
      retries: Keyword.get(opts, :retries, 0),
      elapsed_ms: Keyword.get(opts, :elapsed_ms, 0)
    }
  end

  defp request_id(headers) when is_map(headers) do
    normalized =
      Map.new(headers, fn {key, value} ->
        {String.downcase(to_string(key)), to_string(value)}
      end)

    normalized["x-request-id"] ||
      normalized["x-system-one-request-id"] ||
      normalized["x-typesafe-request-id"]
  end
end
