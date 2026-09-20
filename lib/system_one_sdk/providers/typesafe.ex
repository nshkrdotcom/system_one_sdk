defmodule SystemOneSDK.Providers.TypeSafe do
  @moduledoc """
  Built-in TypeSafe provider backed by `TypeSafeAPISDK`.

  The semantic SDK supplies already-prepared System One wire values. TypeSafe
  HTTP, authentication, endpoint handling, OpenAPI operations, retries, and
  transport execution remain owned by `typesafe_api_sdk`.
  """

  @behaviour SystemOneSDK.Provider

  alias SystemOneSDK.{
    Error,
    ListModelsResponse,
    SystemOneResponse
  }

  @system_one_local_options [:model, :extra_body]

  @error_fields [
    :type,
    :message,
    :status,
    :body,
    :headers,
    :request_id,
    :retry_after_ms,
    :field_path,
    :path,
    :endpoint,
    :raw_http_response,
    :details
  ]

  @impl true
  def id, do: :typesafe

  @impl true
  def new_client(opts) do
    TypeSafeAPISDK.new_client(opts)
  rescue
    error in TypeSafeAPISDK.Error ->
      raise normalize_error(error)
  end

  @impl true
  def default_model(%TypeSafeAPISDK.Client{default_model: model}), do: model

  @impl true
  def system_one(client, state, questions, opts) when is_list(opts) do
    body =
      %{
        "state" => state,
        "model" => Keyword.get(opts, :model) || client.default_model,
        "questions" => questions
      }
      |> Map.merge(normalize_extra_body(Keyword.get(opts, :extra_body, %{})))

    request_opts = Keyword.drop(opts, @system_one_local_options)

    case TypeSafeAPISDK.Generated.SystemOne.create(
           client,
           body,
           request_opts
         ) do
      {:ok, wire_response} ->
        case TypeSafeAPISDK.SystemOneResponse.decode(wire_response) do
          {:ok, response} -> convert_system_one(response)
          {:error, error} -> {:error, normalize_error(error)}
        end

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  @impl true
  def list_models(client, opts) do
    case TypeSafeAPISDK.list_models(client, opts) do
      {:ok, response} -> convert_models(response)
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  @impl true
  def capabilities(client),
    do: TypeSafeAPISDK.RuntimeCapabilities.report(client)

  defp convert_system_one(%TypeSafeAPISDK.SystemOneResponse{} = source) do
    case SystemOneResponse.decode(source.raw) do
      {:ok, response} ->
        {:ok,
         %{
           response
           | request_id: source.request_id,
             raw_http_response: source.raw_http_response,
             raw: source.raw,
             retries: source.retries,
             elapsed_ms: source.elapsed_ms
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp convert_models(%TypeSafeAPISDK.ListModelsResponse{} = source) do
    case ListModelsResponse.decode(source.raw) do
      {:ok, response} ->
        {:ok,
         %{
           response
           | request_id: source.request_id,
             raw_http_response: source.raw_http_response,
             raw: source.raw,
             retries: source.retries,
             elapsed_ms: source.elapsed_ms
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_extra_body(nil), do: %{}

  defp normalize_extra_body(map)
       when is_map(map) and not is_struct(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), value}
    end)
  end

  defp normalize_extra_body(other) do
    raise ArgumentError,
          "extra_body must be a map, got: #{inspect(other)}"
  end

  defp normalize_error(%TypeSafeAPISDK.Error{
         type: :cancelled,
         cause: %Pristine.Error{type: :cancelled} = cause
       }) do
    Error.cancelled(cause)
  end

  defp normalize_error(%TypeSafeAPISDK.Error{} = source) do
    attrs =
      source
      |> Map.from_struct()
      |> Map.take(@error_fields)
      |> Map.put(:cause, source)

    struct(Error, attrs)
  end

  defp normalize_error(%Error{} = error), do: error

  defp normalize_error(other) do
    %Error{
      type: :api_error,
      message: "System One provider request failed",
      cause: other,
      details: %{provider: :typesafe}
    }
  end
end
