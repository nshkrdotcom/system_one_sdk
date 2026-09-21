defmodule SystemOneSDK.Providers.Endpoint do
  @moduledoc """
  Generic System One v1 HTTP endpoint provider backed directly by Pristine.

  Use this for any compatible `POST /v1/systemone` + `GET /v1/models` endpoint.
  TypeSafe-specific auth, schemas and OpenAPI maintenance remain in
  `SystemOneSDK.Providers.TypeSafe` / `typesafe_api_sdk`.
  """

  @behaviour SystemOneSDK.Provider

  alias Pristine.Adapters.Auth.Bearer
  alias SystemOneContracts.V1.{ModelsResponse, Response}
  alias SystemOneSDK.{ContractBridge, Error, RetryPolicy}
  alias SystemOneSDK.Providers.Endpoint.TransportResponse

  defmodule Client do
    @moduledoc false
    defstruct [
      :api_key,
      :base_url,
      :default_model,
      :timeout_ms,
      :retry,
      :headers,
      :transport,
      :transport_opts,
      :context,
      :pristine_client
    ]
  end

  @impl true
  def id, do: :endpoint

  @impl true
  def new_client(opts) when is_list(opts) do
    api_key = optional_api_key(Keyword.get(opts, :api_key))
    base_url = validate_base_url!(Keyword.get(opts, :base_url))
    model = validate_model!(Keyword.get(opts, :model))
    timeout_ms = validate_timeout_ms!(Keyword.get(opts, :timeout_ms, 30_000))
    retry = resolve_retry(Keyword.get(opts, :retry, false))
    headers = normalize_headers(Keyword.get(opts, :headers, %{}))
    transport = Keyword.get(opts, :transport, Pristine.Adapters.Transport.Finch)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    client = %Client{
      api_key: api_key,
      base_url: base_url,
      default_model: model,
      timeout_ms: timeout_ms,
      retry: retry,
      headers: headers,
      transport: transport,
      transport_opts: transport_opts
    }

    context = build_context(client)
    %{client | context: context, pristine_client: Pristine.Client.from_context(context)}
  end

  @impl true
  def default_model(%Client{default_model: model}), do: model

  @impl true
  def system_one(%Client{} = client, state, questions, opts) when is_list(opts) do
    execute_system_one(client, state, questions, opts)
  end

  @impl true
  def system_one_prepared(%Client{} = client, state, prepared, opts) when is_list(opts) do
    execute_system_one(client, state, prepared, opts)
  end

  @impl true
  def list_models(%Client{} = client, opts) when is_list(opts) do
    with {:ok, %TransportResponse{} = wrapped} <- execute(client, :get, "/v1/models", nil, opts),
         {:ok, contract_response} <- ModelsResponse.decode(wrapped.data),
         {:ok, response} <-
           ContractBridge.models_from_contract(
             attach_models_metadata(contract_response, wrapped)
           ) do
      {:ok,
       %{
         response
         | raw_http_response: wrapped.raw_http_response,
           retries: wrapped.retries,
           elapsed_ms: wrapped.elapsed_ms
       }}
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  @impl true
  def capabilities(%Client{pristine_client: pristine}) do
    report = Pristine.RuntimeCapabilities.transport(pristine)

    %{
      transport: inspect(report.adapter),
      runtime: report.capabilities,
      system_one: %{
        protocol: SystemOneContracts.protocol(),
        capabilities: SystemOneContracts.Capabilities.core()
      },
      assurance: :pristine_transport_contract
    }
  end

  defp execute_system_one(client, state, questions, opts) do
    model = Keyword.get(opts, :model) || client.default_model
    extra = normalize_extra(Keyword.get(opts, :extra_body, %{}))

    with {:ok, request} <- ContractBridge.request(state, questions, model, extra),
         {:ok, %TransportResponse{} = wrapped} <-
           execute(
             client,
             :post,
             "/v1/systemone",
             SystemOneContracts.V1.Request.to_map(request),
             opts
           ),
         {:ok, contract_response} <- Response.decode(wrapped.data),
         {:ok, response} <-
           ContractBridge.response_from_contract(attach_metadata(contract_response, wrapped)) do
      {:ok,
       %{
         response
         | raw_http_response: wrapped.raw_http_response,
           retries: wrapped.retries,
           elapsed_ms: wrapped.elapsed_ms
       }}
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  defp execute(client, method, path, body, opts) do
    request = %{
      id: if(method == :post, do: "system_one", else: "list_models"),
      method: method,
      path: path,
      path_params: %{},
      query: %{},
      headers: normalize_headers(Keyword.get(opts, :extra_headers, %{})),
      body: body,
      form_data: nil,
      auth: request_auth(client),
      security: nil,
      request_schema: nil,
      response_schema: nil,
      use_default_auth: false,
      resource: if(method == :post, do: "system_one", else: "models")
    }

    retry = RetryPolicy.merge!(client.retry, Keyword.get(opts, :retry))

    execute_opts =
      []
      |> maybe_put(:timeout, timeout_override(opts))
      |> maybe_put(:cancellation, Keyword.get(opts, :cancellation))
      |> Keyword.put(:retry_opts, RetryPolicy.to_pristine_opts(retry))
      |> Keyword.put(:response, :wrapped)

    Pristine.execute_request(request, client.context, execute_opts)
  end

  defp build_context(client) do
    Pristine.foundation_context(
      auth: [],
      base_url: client.base_url,
      default_timeout: client.timeout_ms,
      headers: Map.merge(client.headers, system_headers()),
      package_version: SystemOneSDK.version(),
      response_wrapper: TransportResponse,
      retry: [
        adapter: Pristine.Adapters.Retry.Foundation,
        opts: RetryPolicy.to_pristine_opts(client.retry)
      ],
      serializer: Pristine.Adapters.Serializer.JSON,
      transport: client.transport,
      transport_opts: client.transport_opts
    )
  end

  defp request_auth(%Client{api_key: nil}), do: []
  defp request_auth(%Client{api_key: api_key}), do: [Bearer.new(api_key)]

  defp system_headers do
    sdk = "system-one-sdk/#{SystemOneSDK.version()}"
    %{"Accept" => "application/json", "User-Agent" => sdk}
  end

  defp attach_metadata(%Response{} = response, wrapped) do
    %{
      response
      | request_id: wrapped.request_id,
        metadata: %{method: wrapped.method, url: wrapped.url}
    }
  end

  defp attach_models_metadata(%ModelsResponse{} = response, wrapped) do
    %{
      response
      | request_id: wrapped.request_id,
        metadata: %{method: wrapped.method, url: wrapped.url}
    }
  end

  defp normalize_error(%Error{} = error), do: error

  defp normalize_error(%SystemOneContracts.Error{} = error) do
    %Error{
      type: if(error.type == :invalid_response, do: :response_validation, else: :invalid_request),
      message: error.message,
      path: error.path,
      field_path: if(error.path, do: Enum.join(error.path, ".")),
      cause: error,
      details: error.details
    }
  end

  defp normalize_error(%Pristine.Error{} = error) do
    %Error{
      type: pristine_error_type(error.type),
      message: error.message || "System One endpoint request failed",
      status: error.status,
      body: error.body,
      headers: error.headers || %{},
      request_id: error.request_id,
      retry_after_ms: error.retry_after_ms,
      cause: error,
      details: %{provider: :endpoint}
    }
  end

  defp normalize_error(other) do
    %Error{
      type: :api_error,
      message: "System One endpoint request failed",
      cause: other,
      details: %{provider: :endpoint}
    }
  end

  defp pristine_error_type(type)
       when type in [
              :bad_request,
              :authentication,
              :permission_denied,
              :not_found,
              :unprocessable_entity,
              :rate_limit,
              :internal_server,
              :timeout,
              :connection,
              :cancelled
            ],
       do: type

  defp pristine_error_type(_), do: :api_error

  defp optional_api_key(nil), do: nil

  defp optional_api_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_api_key(_), do: raise(Error.configuration("api_key must be a string or nil"))

  defp validate_base_url!(value) when is_binary(value) do
    value = String.trim(value)
    uri = URI.parse(value)

    cond do
      value == "" -> raise Error.configuration("base_url must not be blank")
      uri.scheme not in ["http", "https"] ->
        raise Error.configuration("base_url must use http or https")
      is_nil(uri.host) or uri.host == "" ->
        raise Error.configuration("base_url must include a host")
      not is_nil(uri.userinfo) ->
        raise Error.configuration("base_url must not contain URL credentials")
      not is_nil(uri.query) -> raise Error.configuration("base_url must not contain a query string")
      not is_nil(uri.fragment) -> raise Error.configuration("base_url must not contain a fragment")
      true -> String.trim_trailing(value, "/")
    end
  end

  defp validate_base_url!(_), do: raise(Error.configuration("base_url must be an http(s) URL"))

  defp validate_model!(value) when is_binary(value) do
    case String.trim(value) do
      "" -> raise Error.configuration("model must not be blank")
      trimmed -> trimmed
    end
  end

  defp validate_model!(_), do: raise(Error.configuration("model must be a nonblank string"))

  defp validate_timeout_ms!(value) when is_integer(value) and value > 0, do: value

  defp validate_timeout_ms!(value) when is_float(value) and value > 0 and value < 1.0e12,
    do: round(value)

  defp validate_timeout_ms!(_), do: raise(Error.configuration("timeout_ms must be positive"))

  defp resolve_retry(false), do: false
  defp resolve_retry(nil), do: false
  defp resolve_retry(%RetryPolicy{} = retry), do: retry
  defp resolve_retry(value) when is_list(value) or is_map(value), do: RetryPolicy.new!(value)
  defp resolve_retry(other),
    do: raise(Error.configuration("invalid retry policy: #{inspect(other)}"))

  defp normalize_extra(nil), do: %{}
  defp normalize_extra(extra) when is_map(extra) and not is_struct(extra), do: extra
  defp normalize_extra(other),
    do: raise(ArgumentError, "extra_body must be a map, got: #{inspect(other)}")

  defp normalize_headers(nil), do: %{}

  defp normalize_headers(headers) when is_map(headers) or is_list(headers) do
    Map.new(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_headers(_),
    do: raise(Error.configuration("headers must be a map or key/value list"))

  defp timeout_override(opts) do
    cond do
      Keyword.has_key?(opts, :timeout_ms) and not is_nil(Keyword.get(opts, :timeout_ms)) ->
        validate_timeout_ms!(Keyword.fetch!(opts, :timeout_ms))

      Keyword.has_key?(opts, :timeout) and not is_nil(Keyword.get(opts, :timeout)) ->
        seconds_to_ms!(Keyword.fetch!(opts, :timeout))

      true ->
        nil
    end
  end

  defp seconds_to_ms!(value) when is_number(value) and value > 0 and value < 1.0e9,
    do: round(value * 1_000)

  defp seconds_to_ms!(_), do: raise(Error.configuration("timeout must be positive and finite"))
  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
