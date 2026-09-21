defmodule SystemOneSDK.Client do
  @moduledoc """
  Provider-neutral System One client.

  A client contains a provider module plus opaque provider state. The default
  provider is `SystemOneSDK.Providers.TypeSafe`, backed by `TypeSafeAPISDK`.

  During the 0.5.0 extraction, selected low-level fields are mirrored from the
  provider client so the existing semantic test/runtime suite can be migrated
  incrementally. Provider execution itself goes through the provider behaviour.
  """

  alias SystemOneSDK.{
    Error,
    RequestBudget,
    ResponseContract,
    RuntimeCapabilities
  }

  alias SystemOneSDK.Providers.TypeSafe

  @generic_options [
    :provider,
    :provider_opts,
    :response_contract,
    :max_request_bytes,
    :runtime_requirements
  ]

  @type t :: %__MODULE__{
          provider: module(),
          provider_client: term(),
          default_model: String.t(),
          response_contract: map(),
          max_request_bytes: pos_integer() | nil,
          api_key: term(),
          base_url: term(),
          timeout_ms: term(),
          retry: term(),
          headers: term(),
          transport: term(),
          transport_opts: term(),
          context: term(),
          pristine_client: term()
        }

  defstruct [
    :provider,
    :provider_client,
    :default_model,
    :response_contract,
    :max_request_bytes,
    :api_key,
    :base_url,
    :timeout_ms,
    :retry,
    :headers,
    :transport,
    :transport_opts,
    :context,
    :pristine_client
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "client options must be a keyword list"
    end

    provider =
      Keyword.get(
        opts,
        :provider,
        Application.get_env(:system_one_sdk, :provider, TypeSafe)
      )

    ensure_provider!(provider)

    provider_opts = provider_options(opts, provider)
    provider_client = provider.new_client(provider_opts)

    response_contract =
      opts
      |> option_or_config(:response_contract, nil)
      |> resolve_response_contract()

    max_request_bytes =
      opts
      |> option_or_config(:max_request_bytes, nil)
      |> resolve_max_request_bytes()

    client = %__MODULE__{
      provider: provider,
      provider_client: provider_client,
      default_model: provider.default_model(provider_client),
      response_contract: response_contract,
      max_request_bytes: max_request_bytes,
      api_key: mirrored(provider_client, :api_key),
      base_url: mirrored(provider_client, :base_url),
      timeout_ms: mirrored(provider_client, :timeout_ms),
      retry: mirror_retry(mirrored(provider_client, :retry)),
      headers: mirrored(provider_client, :headers),
      transport: mirrored(provider_client, :transport),
      transport_opts: mirrored(provider_client, :transport_opts),
      context: mirrored(provider_client, :context),
      pristine_client: mirrored(provider_client, :pristine_client)
    }

    RuntimeCapabilities.require!(
      client,
      Keyword.get(opts, :runtime_requirements, [])
    )

    client
  end

  @doc false
  def provider_client(%__MODULE__{provider_client: client}), do: client

  @doc false
  def system_one(%__MODULE__{} = client, state, questions, opts \\ []) do
    client.provider.system_one(client.provider_client, state, questions, opts)
  end

  @doc false
  def system_one_prepared(%__MODULE__{} = client, state, prepared, opts \\ []) do
    if function_exported?(client.provider, :system_one_prepared, 4) do
      client.provider.system_one_prepared(client.provider_client, state, prepared, opts)
    else
      client.provider.system_one(
        client.provider_client,
        state,
        SystemOneSDK.Prepared.encoded(prepared),
        opts
      )
    end
  end

  @doc false
  def list_models(%__MODULE__{} = client, opts \\ []) do
    client.provider.list_models(client.provider_client, opts)
  end

  @doc false
  def capabilities(%__MODULE__{} = client) do
    client.provider.capabilities(client.provider_client)
  end

  # Temporary compatibility for copied generated modules until the TypeSafe
  # generated/codegen layer is removed from this repository.
  @doc false
  def pristine_client(%__MODULE__{pristine_client: %Pristine.Client{} = client}), do: client

  @doc false
  def execute_generated_request(
        %__MODULE__{provider: TypeSafe, provider_client: provider_client},
        request
      ) do
    TypeSafeAPISDK.Client.execute_generated_request(provider_client, request)
  end

  @doc false
  def extra_headers(opts), do: TypeSafeAPISDK.Client.extra_headers(opts)

  defp provider_options(opts, provider) do
    provider_opts =
      opts
      |> Keyword.drop(@generic_options)
      |> maybe_inherit_typesafe_options(provider)

    explicit = Keyword.get(opts, :provider_opts, [])

    unless Keyword.keyword?(explicit) do
      raise ArgumentError, ":provider_opts must be a keyword list"
    end

    Keyword.merge(provider_opts, explicit)
  end

  defp maybe_inherit_typesafe_options(opts, TypeSafe) do
    opts
    |> inherit_provider_option(:api_key, :api_key)
    |> inherit_provider_option(:base_url, :base_url)
    |> inherit_provider_option(:model, :default_model)
    |> inherit_timeout()
    |> inherit_provider_option(:retry, :retry)
    |> inherit_provider_option(:headers, :headers)
    |> inherit_provider_option(:transport, :transport)
    |> inherit_provider_option(:transport_opts, :transport_opts)
  end

  defp maybe_inherit_typesafe_options(opts, _provider), do: opts

  defp inherit_provider_option(opts, provider_key, config_key) do
    case Keyword.fetch(opts, provider_key) do
      {:ok, value} when not is_nil(value) ->
        opts

      _ ->
        opts = Keyword.delete(opts, provider_key)

        case Application.fetch_env(:system_one_sdk, config_key) do
          {:ok, nil} -> opts
          {:ok, value} -> Keyword.put(opts, provider_key, value)
          :error -> opts
        end
    end
  end

  defp inherit_timeout(opts) do
    if non_nil_keyword?(opts, :timeout) or
         non_nil_keyword?(opts, :timeout_ms) do
      opts
    else
      opts =
        opts
        |> Keyword.delete(:timeout)
        |> Keyword.delete(:timeout_ms)

      case Application.fetch_env(:system_one_sdk, :timeout_ms) do
        {:ok, nil} -> opts
        {:ok, value} -> Keyword.put(opts, :timeout_ms, value)
        :error -> opts
      end
    end
  end

  defp non_nil_keyword?(opts, key) do
    Keyword.has_key?(opts, key) and
      not is_nil(Keyword.get(opts, key))
  end

  defp ensure_provider!(provider) when is_atom(provider) do
    with {:module, _} <- Code.ensure_loaded(provider),
         true <- function_exported?(provider, :new_client, 1),
         true <- function_exported?(provider, :default_model, 1),
         true <- function_exported?(provider, :system_one, 4),
         true <- function_exported?(provider, :list_models, 2),
         true <- function_exported?(provider, :capabilities, 1) do
      :ok
    else
      _ ->
        raise Error.configuration("invalid System One provider #{inspect(provider)}")
    end
  end

  defp ensure_provider!(provider),
    do: raise(Error.configuration("invalid System One provider #{inspect(provider)}"))

  defp resolve_response_contract(value) do
    case ResponseContract.normalize(value) do
      {:ok, contract} -> contract
      {:error, error} -> raise error
    end
  end

  defp resolve_max_request_bytes(value) do
    case RequestBudget.validate(value, ["max_request_bytes"]) do
      :ok -> value
      {:error, error} -> raise error
    end
  end

  defp option_or_config(opts, key, fallback) do
    case Keyword.fetch(opts, key) do
      {:ok, nil} -> Application.get_env(:system_one_sdk, key, fallback)
      {:ok, value} -> value
      :error -> Application.get_env(:system_one_sdk, key, fallback)
    end
  end

  defp mirrored(value, key) when is_map(value), do: Map.get(value, key)
  defp mirrored(_value, _key), do: nil

  defp mirror_retry(false), do: false
  defp mirror_retry(nil), do: nil

  defp mirror_retry(%TypeSafeAPISDK.RetryPolicy{} = retry) do
    struct(SystemOneSDK.RetryPolicy, Map.from_struct(retry))
  end

  defp mirror_retry(retry), do: retry
end
