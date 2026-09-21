defmodule SystemOneSDK.RuntimeCapabilities do
  @moduledoc """
  Fail-closed runtime capability view across System One providers.

  Client providers report capabilities through the provider contract. Direct
  Pristine clients/contexts continue to use `Pristine.RuntimeCapabilities`.
  """

  alias SystemOneSDK.{Client, Error}

  @capabilities [
    :unary_cancellation,
    :cancellation_cleanup,
    :bounded_outstanding_requests,
    :bounded_queue,
    :max_response_bytes,
    :deterministic_overload
  ]

  @spec names() :: [atom()]
  def names, do: @capabilities

  @spec report(Client.t() | Pristine.Client.t() | Pristine.Core.Context.t()) :: map()
  def report(%Client{} = client) do
    client
    |> Client.capabilities()
    |> normalize_client_report()
  end

  def report(source) do
    pristine = Pristine.RuntimeCapabilities.transport(pristine_source(source))

    %{
      transport: inspect(pristine.adapter),
      runtime: normalize_runtime(pristine.capabilities),
      sdk: sdk_capabilities(),
      assurance: :pristine_transport_contract
    }
  end

  @spec check(Client.t() | Pristine.Client.t() | Pristine.Core.Context.t(), [atom()]) ::
          :ok | {:error, Error.t()}
  def check(_client, []), do: :ok

  def check(client, requirements) when is_list(requirements) do
    runtime = report(client).runtime

    missing =
      Enum.reject(requirements, fn name ->
        is_atom(name) and get_in(runtime, [name, :status]) == :supported
      end)

    if missing == [] do
      :ok
    else
      statuses =
        Map.new(missing, fn name ->
          {name, get_in(runtime, [name, :status]) || :unverified}
        end)

      {:error,
       %Error{
         type: :runtime_capability,
         message: "Required runtime capabilities are not supported: #{inspect(missing)}",
         details: %{missing: missing, statuses: statuses}
       }}
    end
  end

  def check(_, _),
    do:
      {:error,
       Error.invalid_request(["runtime_requirements"], "must be a list of capability atoms")}

  @spec require!(Client.t() | Pristine.Client.t() | Pristine.Core.Context.t(), [atom()]) :: :ok
  def require!(client, requirements) do
    case check(client, requirements) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  defp normalize_client_report(%{runtime: runtime} = report) when is_map(runtime) do
    report
    |> Map.put(:runtime, normalize_runtime(runtime))
    |> Map.put_new(:sdk, sdk_capabilities())
  end

  defp normalize_client_report(report) when is_map(report) do
    %{
      transport: Map.get(report, :transport),
      runtime: normalize_runtime(%{}),
      system_one: report,
      sdk: sdk_capabilities(),
      assurance: Map.get(report, :assurance, :provider_contract)
    }
  end

  defp normalize_runtime(runtime) do
    Map.new(@capabilities, fn capability ->
      {capability, Map.get(runtime, capability, %{status: :unverified})}
    end)
  end

  defp sdk_capabilities do
    %{
      batch_concurrency: :limited_per_enumeration,
      batch_queue: :lazy_enumeration,
      ordered_prefetch: :limited_windows,
      batch_cancellation: :shared_pristine_token
    }
  end

  defp pristine_source(%Pristine.Client{} = client), do: client
  defp pristine_source(%Pristine.Core.Context{} = context), do: context

end
