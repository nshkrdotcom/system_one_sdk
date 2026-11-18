defmodule SystemOneSDK.Providers.GeminiDecisions do
  @moduledoc """
  `SystemOneSDK.Provider` implementation for the Gemini Decisions API (`gemini-decision-1`).

  Supports both:

  - **Unified LiteLLM `/v1/decisions`** (`decisions_mode: :unified`, `Authorization: Bearer`)
  - **Native Gemini `/v1beta/decisions` or `/gemini/v1beta/decisions` passthrough**
    (`decisions_mode: :native`, `x-goog-api-key`)

  Create separate clients via `SystemOneSDK.new_client/1` for distinct modes, endpoints, or keys;
  per-call overrides follow `SystemOneSDK` evaluation options (`:model`, `:timeout`, `:timeout_ms`,
  `:retry`, `:extra_body`, `:extra_headers`, `:cancellation`).

  ## Options

  - `:decisions_mode` - `:unified` (default) or `:native`.
  - `:auth_mode` - `:bearer` (default for `:unified`), `:x_goog_api_key` (default for `:native`),
    or `:none`.
  - `:base_url` - Base endpoint URL. Defaults to `LITELLM_BASE_URL` in `:unified` mode (required)
    and `GEMINI_DECISIONS_BASE_URL` or `"https://generativelanguage.googleapis.com"` in `:native` mode.
  - `:decisions_path` - Explicit path override (otherwise inferred as `/v1/decisions`,
    `/v1beta/decisions`, or `/decisions` when `base_url` already ends in `/v1` or `/v1beta`).
  - `:api_key` / `:gemini_api_key` - API key string, `false` to suppress env fallback, or secret
    resolver (`{:system, "ENV"}`, `{:system, "ENV", default}`, 0-arity function, or `{mod, fun, args}`).
  - `:model` - Default model name (defaults to `"gemini-decision-1"`).
  - `:timeout` - Request timeout in seconds (default `30`).
  - `:timeout_ms` - Request timeout in milliseconds (default `30_000`; takes precedence over `:timeout`).
  - `:retry` - `SystemOneSDK.RetryPolicy` overrides or `false`.
  - `:headers` - Extra default HTTP headers.
  - `:transport` / `:transport_opts` - Custom `Pristine` transport adapter and options.
  """

  @behaviour SystemOneSDK.Provider

  alias SystemOneSDK.{
    Error,
    ListModelsResponse,
    Prepared,
    RetryPolicy,
    SystemOneResponse,
    TransportError
  }

  alias SystemOneSDK.Providers.Endpoint.TransportResponse
  alias SystemOneSDK.Providers.GeminiDecisions.Protocol

  @default_native_base_url "https://generativelanguage.googleapis.com"
  @default_model "gemini-decision-1"
  @default_timeout_ms 30_000

  defmodule Client do
    @moduledoc false

    @type t :: %__MODULE__{
            api_key: String.t() | nil,
            base_url: String.t() | nil,
            default_model: String.t(),
            decisions_mode: Protocol.mode(),
            auth_mode: Protocol.auth_mode(),
            decisions_path: String.t(),
            timeout_ms: pos_integer(),
            retry: RetryPolicy.t() | false,
            headers: %{optional(String.t()) => String.t()},
            transport: module(),
            transport_opts: keyword(),
            context: Pristine.SDK.Context.t() | nil,
            pristine_client: Pristine.Client.t() | nil
          }

    defstruct [
      :api_key,
      :base_url,
      :default_model,
      :decisions_mode,
      :auth_mode,
      :decisions_path,
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
  @spec id() :: :gemini_decisions
  def id, do: :gemini_decisions

  @impl true
  @spec new_client(keyword()) :: Client.t()
  def new_client(opts) when is_list(opts) do
    %Client{} = client = build_client(opts)

    if not non_blank_binary?(client.base_url) do
      raise configuration_error(
              missing_base_url_message(client.decisions_mode),
              %{decisions_mode: client.decisions_mode}
            )
    end

    context = build_context(client)
    %Client{client | context: context, pristine_client: Pristine.Client.from_context(context)}
  end

  defp build_client(opts) do
    :ok = validate_provider_opts!(opts)

    decisions_mode = Keyword.get(opts, :decisions_mode) || :unified
    auth_mode = Keyword.get(opts, :auth_mode) || default_auth_mode(decisions_mode)
    otp_app = Keyword.get(opts, :otp_app)

    raw_base_url = resolve_base_url(opts, decisions_mode)
    api_key = resolve_initial_api_key(opts, decisions_mode, otp_app)

    {base_url, decisions_path} =
      normalize_base_url_and_path(opts, decisions_mode, raw_base_url)

    %Client{
      api_key: api_key,
      base_url: base_url,
      default_model: Keyword.get(opts, :model) || @default_model,
      decisions_mode: decisions_mode,
      auth_mode: auth_mode,
      decisions_path: decisions_path,
      timeout_ms: resolve_initial_timeout_ms!(opts),
      retry: resolve_retry(Keyword.get(opts, :retry)),
      headers: normalize_headers!(Keyword.get(opts, :headers)),
      transport: Keyword.get(opts, :transport) || Pristine.Adapters.Transport.Finch,
      transport_opts: Keyword.get(opts, :transport_opts) || []
    }
  end

  defp default_auth_mode(:native), do: :x_goog_api_key
  defp default_auth_mode(:unified), do: :bearer

  defp default_auth_mode(other) do
    raise configuration_error(
            "Invalid :decisions_mode #{inspect(other)}. Expected :unified or :native.",
            %{decisions_mode: other}
          )
  end

  @impl true
  @spec default_model(Client.t()) :: String.t()
  def default_model(%Client{default_model: model}), do: model

  @impl true
  @spec system_one(Client.t(), term(), term(), keyword()) ::
          {:ok, SystemOneResponse.t()} | {:error, Error.t()}
  def system_one(%Client{} = client, state, questions, opts) when is_list(opts) do
    case SystemOneSDK.prepare(questions) do
      {:ok, %Prepared{} = prepared} -> system_one_prepared(client, state, prepared, opts)
      {:error, _} = err -> err
    end
  end

  @impl true
  @spec system_one_prepared(Client.t(), term(), Prepared.t(), keyword()) ::
          {:ok, SystemOneResponse.t()} | {:error, Error.t()}
  def system_one_prepared(%Client{} = client, state, %Prepared{} = prepared, opts)
      when is_list(opts) do
    with :ok <- validate_client_modes(client),
         {:ok, model} <- resolve_call_model(client, opts),
         {:ok, call_headers} <- normalize_headers_safe(Keyword.get(opts, :extra_headers)),
         {:ok, retry} <- RetryPolicy.merge(client.retry, Keyword.get(opts, :retry)),
         {:ok, timeout_ms} <- timeout_override_safe(opts),
         {:ok, extra_body} <- normalize_extra_body(Keyword.get(opts, :extra_body)),
         {:ok, encoded_req} <-
           Protocol.encode_request_safe(state, prepared, model, client.decisions_mode) do
      body = Map.merge(extra_body, encoded_req)

      dispatch_prepared_request(
        client,
        prepared,
        model,
        body,
        call_headers,
        retry,
        timeout_ms,
        opts
      )
    end
  end

  defp resolve_call_model(%Client{default_model: default_model}, opts) do
    case Keyword.get(opts, :model) do
      nil -> validate_model_value(default_model)
      model -> validate_model_value(model)
    end
  end

  defp validate_model_value(model) when is_binary(model) do
    if non_blank_binary?(model),
      do: {:ok, model},
      else: {:error, Error.configuration("model must not be blank")}
  end

  defp validate_model_value(other) do
    {:error, Error.configuration("Invalid :model #{inspect(other)}. Expected a string.")}
  end

  defp dispatch_prepared_request(
         %Client{} = client,
         %Prepared{} = prepared,
         model,
         body,
         call_headers,
         retry,
         timeout_ms,
         opts
       ) do
    extra_headers =
      client.api_key
      |> Protocol.auth_headers(client.auth_mode)
      |> merge_headers_case_insensitive(call_headers)

    request = %{
      id: "gemini_decisions",
      method: :post,
      path: client.decisions_path,
      path_params: %{},
      query: %{},
      headers: extra_headers,
      body: body,
      form_data: nil,
      auth: [],
      security: nil,
      request_schema: nil,
      response_schema: nil,
      use_default_auth: false,
      resource: "decisions"
    }

    execute_opts =
      [
        retry_opts: RetryPolicy.to_pristine_opts(retry),
        response: :wrapped
      ]
      |> maybe_put(:timeout, timeout_ms)
      |> maybe_put(:cancellation, Keyword.get(opts, :cancellation))

    with {:ok, %TransportResponse{} = wrapped} <-
           Pristine.execute_request(request, client.context, execute_opts),
         {:ok, decoded} <- ensure_decoded_map(wrapped.data),
         {:ok, %SystemOneResponse{} = response} <-
           Protocol.decode_response(decoded, prepared, model) do
      {:ok,
       %SystemOneResponse{
         response
         | request_id: wrapped.request_id,
           raw_http_response: wrapped.raw_http_response,
           retries: wrapped.retries,
           elapsed_ms: wrapped.elapsed_ms
       }}
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  @impl true
  @spec list_models(Client.t(), keyword()) ::
          {:ok, ListModelsResponse.t()} | {:error, Error.t()}
  def list_models(%Client{}, _opts), do: {:ok, %ListModelsResponse{models: []}}

  @impl true
  @spec capabilities(Client.t()) :: map()
  def capabilities(%Client{pristine_client: pristine, decisions_mode: mode, auth_mode: auth_mode}) do
    report = Pristine.RuntimeCapabilities.transport(pristine)

    %{
      provider: :gemini_decisions,
      decisions_mode: mode,
      auth_mode: auth_mode,
      transport: inspect(report.adapter),
      runtime: report.capabilities
    }
  end

  @doc false
  def resolve_secret(raw) do
    case resolve_secret_safe(raw) do
      {:ok, val} -> val
      {:error, %Error{} = err} -> raise err
    end
  end

  defp resolve_secret_safe(nil), do: {:ok, nil}
  defp resolve_secret_safe(false), do: {:ok, nil}
  defp resolve_secret_safe(str) when is_binary(str), do: {:ok, String.trim(str)}

  defp resolve_secret_safe({:system, env_var}) when is_binary(env_var) do
    resolve_secret_safe(System.get_env(env_var))
  end

  defp resolve_secret_safe({:system, env_var, default}) when is_binary(env_var) do
    case non_blank_secret(System.get_env(env_var)) do
      nil -> resolve_secret_safe(default)
      val -> {:ok, val}
    end
  end

  defp resolve_secret_safe(fun) when is_function(fun, 0), do: resolve_secret_safe(fun.())

  defp resolve_secret_safe({mod, fun, args})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    apply(mod, fun, args) |> resolve_secret_safe()
  end

  defp resolve_secret_safe(other) do
    {:error, Error.configuration("Invalid secret or URL configuration value: #{inspect(other)}")}
  end

  defp non_blank_secret(val) when is_binary(val) do
    case String.trim(val) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_blank_secret(_), do: nil

  defp resolve_initial_api_key(opts, decisions_mode, otp_app) do
    case resolve_explicit_key_opt(opts, :api_key) do
      {:found, val} ->
        val

      :unset ->
        case resolve_explicit_key_opt(opts, :gemini_api_key) do
          {:found, val} -> val
          :unset -> resolve_env_api_key(decisions_mode, otp_app)
        end
    end
  end

  defp resolve_explicit_key_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      :error ->
        :unset

      {:ok, nil} ->
        :unset

      {:ok, false} ->
        {:found, nil}

      {:ok, val} when is_binary(val) ->
        {:found, String.trim(val)}

      {:ok, raw} ->
        case resolve_secret(raw) do
          val when is_binary(val) and val != "" -> {:found, val}
          _ -> {:found, nil}
        end
    end
  end

  defp resolve_env_api_key(:native, otp_app) do
    first_non_blank([
      fn -> otp_app && Application.get_env(otp_app, :gemini_api_key) end,
      fn -> otp_app && Application.get_env(otp_app, :api_key) end,
      fn -> Application.get_env(:system_one_sdk, :gemini_api_key) end,
      fn -> System.get_env("GEMINI_API_KEY") end
    ])
  end

  defp resolve_env_api_key(:unified, otp_app) do
    first_non_blank([
      fn -> otp_app && Application.get_env(otp_app, :litellm_api_key) end,
      fn -> otp_app && Application.get_env(otp_app, :api_key) end,
      fn -> Application.get_env(:system_one_sdk, :litellm_api_key) end,
      fn -> System.get_env("LITELLM_API_KEY") end
    ])
  end

  @doc false
  def resolve_base_url(opts, decisions_mode) when is_list(opts) do
    explicit = resolve_secret(Keyword.get(opts, :base_url))

    if non_blank_binary?(explicit) do
      explicit
    else
      resolve_env_base_url(decisions_mode, Keyword.get(opts, :otp_app))
    end
  end

  defp resolve_env_base_url(:native, otp_app) do
    first_non_blank([
      fn -> otp_app && Application.get_env(otp_app, :gemini_decisions_base_url) end,
      fn -> otp_app && Application.get_env(otp_app, :base_url) end,
      fn -> Application.get_env(:system_one_sdk, :gemini_decisions_base_url) end,
      fn -> System.get_env("GEMINI_DECISIONS_BASE_URL") end,
      fn -> @default_native_base_url end
    ])
  end

  defp resolve_env_base_url(:unified, otp_app) do
    first_non_blank([
      fn -> otp_app && Application.get_env(otp_app, :litellm_base_url) end,
      fn -> otp_app && Application.get_env(otp_app, :base_url) end,
      fn -> Application.get_env(:system_one_sdk, :litellm_base_url) end,
      fn -> System.get_env("LITELLM_BASE_URL") end
    ])
  end

  defp resolve_env_base_url(other, _otp_app) do
    raise configuration_error(
            "Invalid :decisions_mode #{inspect(other)}. Expected :unified or :native.",
            %{decisions_mode: other}
          )
  end

  defp first_non_blank(candidates) do
    Enum.find_value(candidates, fn fun ->
      case resolve_secret(fun.()) do
        val when is_binary(val) and val != "" -> val
        _ -> nil
      end
    end)
  end

  @doc false
  def resolve_decisions_path(opts, decisions_mode, base_url) do
    {normalized_base_url, path} = normalize_base_url_and_path(opts, decisions_mode, base_url)

    if normalized_base_url == base_url do
      path
    else
      ""
    end
  end

  defp normalize_base_url_and_path(opts, decisions_mode, base_url) do
    case Keyword.get(opts, :decisions_path) do
      path when is_binary(path) and path != "" ->
        {base_url, path}

      _ ->
        normalize_mode_base_and_path(decisions_mode, base_url)
    end
  end

  defp normalize_mode_base_and_path(:unified, base_url),
    do: resolve_mode_base_and_path(base_url, "/v1/decisions", "/v1")

  defp normalize_mode_base_and_path(:native, base_url),
    do: resolve_mode_base_and_path(base_url, "/v1beta/decisions", "/v1beta")

  defp normalize_mode_base_and_path(decisions_mode, _base_url) do
    raise configuration_error(
            "Invalid :decisions_mode #{inspect(decisions_mode)}. Expected :unified or :native.",
            %{decisions_mode: decisions_mode}
          )
  end

  defp resolve_mode_base_and_path(base_url, default_path, version_prefix) do
    full_suffix = version_prefix <> "/decisions"
    parsed_path = base_url_path(base_url)

    cond do
      String.ends_with?(parsed_path, full_suffix) ->
        {strip_decisions_suffix(base_url, full_suffix), full_suffix}

      String.ends_with?(parsed_path, version_prefix) ->
        {base_url, "/decisions"}

      true ->
        {base_url, default_path}
    end
  end

  defp base_url_path(nil), do: ""

  defp base_url_path(base_url) when is_binary(base_url) do
    base_url
    |> URI.parse()
    |> Map.get(:path)
    |> Kernel.||("")
    |> String.trim_trailing("/")
  end

  defp strip_decisions_suffix(base_url, suffix) when is_binary(base_url) do
    %URI{} = uri = URI.parse(base_url)
    trimmed = String.trim_trailing(uri.path || "", "/")
    new_path = String.replace_suffix(trimmed, suffix, "")
    URI.to_string(%URI{uri | path: new_path})
  end

  @doc false
  def validate_provider_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with :ok <- validate_opt_in(opts, :decisions_mode, [:unified, :native]),
           :ok <- validate_opt_in(opts, :auth_mode, [:bearer, :x_goog_api_key, :none]),
           :ok <- validate_optional_binary_opt(opts, :model) do
        validate_optional_binary_opt(opts, :decisions_path)
      end
    else
      {:error,
       configuration_error(
         "Invalid provider options #{inspect(opts)}. Expected a keyword list.",
         %{opts: opts}
       )}
    end
  end

  defp validate_provider_opts!(opts) do
    case validate_provider_opts(opts) do
      :ok -> :ok
      {:error, %Error{} = err} -> raise err
    end
  end

  defp validate_client_modes(%Client{decisions_mode: mode, auth_mode: auth}) do
    with :ok <- validate_value_in(mode, :decisions_mode, [:unified, :native]) do
      validate_value_in(auth, :auth_mode, [:bearer, :x_goog_api_key, :none])
    end
  end

  defp validate_opt_in(opts, key, allowed) do
    case Keyword.get(opts, key) do
      nil -> :ok
      val -> validate_value_in(val, key, allowed)
    end
  end

  defp validate_value_in(val, key, allowed) do
    if val in allowed do
      :ok
    else
      {:error,
       configuration_error(
         "Invalid #{inspect(key)} #{inspect(val)}. Expected one of #{inspect(allowed)}.",
         %{key => val}
       )}
    end
  end

  defp validate_optional_binary_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil ->
        :ok

      val when is_binary(val) ->
        if non_blank_binary?(val) do
          :ok
        else
          {:error,
           configuration_error(
             "Invalid #{inspect(key)} #{inspect(val)}. Expected a non-blank binary string.",
             %{key => val}
           )}
        end

      other ->
        {:error,
         configuration_error(
           "Invalid #{inspect(key)} #{inspect(other)}. Expected a non-blank binary string.",
           %{key => other}
         )}
    end
  end

  defp normalize_headers!(headers) do
    case normalize_headers_safe(headers) do
      {:ok, normalized} -> normalized
      {:error, %Error{} = err} -> raise err
    end
  end

  defp normalize_headers_safe(nil), do: {:ok, %{}}

  defp normalize_headers_safe(headers)
       when (is_map(headers) and not is_struct(headers)) or is_list(headers) do
    Enum.reduce_while(headers, {:ok, %{}}, fn
      {k, v}, {:ok, acc} when not is_nil(k) and not is_nil(v) ->
        if String.Chars.impl_for(k) != nil and String.Chars.impl_for(v) != nil do
          {:cont, {:ok, Map.put(acc, to_string(k), to_string(v))}}
        else
          {:halt,
           {:error,
            Error.configuration(
              "headers must contain stringifiable {key, value} pairs, got: #{inspect({k, v})}"
            )}}
        end

      other, _acc ->
        {:halt,
         {:error,
          Error.configuration(
            "headers must be a map or list of {key, value} pairs, got: #{inspect(other)}"
          )}}
    end)
  end

  defp normalize_headers_safe(_) do
    {:error, Error.configuration("headers must be a map or key/value list")}
  end

  defp normalize_extra_body(nil), do: {:ok, %{}}

  defp normalize_extra_body(extra) when is_map(extra) and not is_struct(extra) do
    {:ok, Map.new(extra, fn {k, v} -> {to_string(k), v} end)}
  end

  defp normalize_extra_body(other) do
    {:error,
     Error.invalid_request(
       ["options", "extra_body"],
       "expected :extra_body to be a map, got: #{inspect(other)}",
       %{extra_body: other}
     )}
  end

  defp merge_headers_case_insensitive(base_headers, override_headers) do
    override_downcased =
      override_headers
      |> Map.keys()
      |> MapSet.new(&String.downcase/1)

    base_headers
    |> Enum.reject(fn {k, _v} -> MapSet.member?(override_downcased, String.downcase(k)) end)
    |> Map.new()
    |> Map.merge(override_headers)
  end

  defp build_context(%Client{} = client) do
    Code.ensure_loaded!(TransportResponse)

    Pristine.foundation_context(
      auth: [],
      base_url: client.base_url,
      default_timeout: client.timeout_ms,
      error_module: Error,
      headers: merge_headers_case_insensitive(%{"Accept" => "application/json"}, client.headers),
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

  defp normalize_error(%Error{} = error), do: error

  defp normalize_error(%Pristine.Error{} = error) do
    %Error{
      type: pristine_error_type(error.type),
      message: error.message || "Gemini Decisions request failed",
      status: error.status,
      body: error.body,
      headers: error.headers || %{},
      request_id: error.request_id,
      retry_after_ms: error.retry_after_ms,
      cause: error,
      details: %{provider: :gemini_decisions}
    }
  end

  defp normalize_error(other) do
    if TransportError.timeout?(other) do
      %Error{
        Error.timeout_error()
        | cause: other,
          details: %{provider: :gemini_decisions, reason: other}
      }
    else
      %Error{
        type: :api_error,
        message: "Gemini Decisions request failed: #{inspect(other)}",
        cause: other,
        details: %{provider: :gemini_decisions}
      }
    end
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

  defp configuration_error(message, details) do
    %Error{Error.configuration(message) | details: details}
  end

  defp non_blank_binary?(val) when is_binary(val), do: String.trim(val) != ""
  defp non_blank_binary?(_), do: false

  defp missing_base_url_message(decisions_mode) do
    "Missing :base_url for :gemini_decisions in #{inspect(decisions_mode)} mode. " <>
      "Pass :base_url, configure :litellm_base_url/:base_url, or set LITELLM_BASE_URL."
  end

  defp ensure_decoded_map(data) when is_map(data) and not is_struct(data), do: {:ok, data}

  defp ensure_decoded_map(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      _ ->
        {:error, Error.invalid_response(["response"], "invalid JSON response", data)}
    end
  end

  defp ensure_decoded_map(data) do
    {:error, Error.invalid_response(["response"], "unexpected response payload", data)}
  end

  defp resolve_retry(false), do: false
  defp resolve_retry(nil), do: RetryPolicy.merge!(nil, nil)
  defp resolve_retry(%RetryPolicy{} = retry), do: retry
  defp resolve_retry(value) when is_list(value) or is_map(value), do: RetryPolicy.new!(value)

  defp resolve_retry(other),
    do: raise(Error.configuration("invalid retry policy: #{inspect(other)}"))

  defp resolve_initial_timeout_ms!(opts) do
    case timeout_override_safe(opts) do
      {:ok, nil} -> @default_timeout_ms
      {:ok, timeout_ms} -> timeout_ms
      {:error, %Error{} = err} -> raise err
    end
  end

  defp timeout_override_safe(opts) do
    cond do
      Keyword.has_key?(opts, :timeout_ms) and not is_nil(Keyword.get(opts, :timeout_ms)) ->
        validate_timeout_ms_safe(Keyword.fetch!(opts, :timeout_ms))

      Keyword.has_key?(opts, :timeout) and not is_nil(Keyword.get(opts, :timeout)) ->
        seconds_to_ms_safe(Keyword.fetch!(opts, :timeout))

      true ->
        {:ok, nil}
    end
  end

  defp validate_timeout_ms_safe(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp validate_timeout_ms_safe(value) when is_float(value) and value > 0 and value < 1.0e12 do
    ms = round(value)

    if ms >= 1 do
      {:ok, ms}
    else
      {:error, Error.configuration("timeout_ms must resolve to at least 1 millisecond")}
    end
  end

  defp validate_timeout_ms_safe(_),
    do: {:error, Error.configuration("timeout_ms must be positive and finite")}

  defp seconds_to_ms_safe(value) when is_number(value) and value > 0 and value < 1.0e9 do
    ms = round(value * 1_000)

    if ms >= 1 do
      {:ok, ms}
    else
      {:error, Error.configuration("timeout must resolve to at least 1 millisecond")}
    end
  end

  defp seconds_to_ms_safe(_),
    do: {:error, Error.configuration("timeout must be positive and finite")}

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, val), do: Keyword.put(opts, key, val)
end
