defmodule SystemOneBumblebee.Provider do
  @moduledoc "Native inference implementation of `SystemOneContracts.Provider`."

  @behaviour SystemOneContracts.Provider

  alias SystemOneBumblebee.{
    ModelManifest,
    ModelRegistry,
    RuntimeProfile,
    Serving,
    ServingSupervisor
  }

  alias SystemOneContracts.{Capabilities, Error}
  alias SystemOneContracts.V1.{ModelsResponse, Request, Response}

  defmodule State do
    @moduledoc "Opaque provider state owned by the embedding application."

    @enforce_keys [:registry, :runtime_profile, :load_opts]
    defstruct [:registry, :runtime_profile, :load_opts]

    @type t :: %__MODULE__{
            registry: SystemOneBumblebee.ModelRegistry.t(),
            runtime_profile: SystemOneBumblebee.RuntimeProfile.t(),
            load_opts: keyword()
          }
  end

  @spec new(keyword()) :: {:ok, State.t()} | {:error, term()}
  def new(opts \\ []) when is_list(opts) do
    models = Keyword.get(opts, :models, Application.get_env(:system_one_bumblebee, :models, %{}))
    profile = Keyword.get(opts, :runtime_profile, RuntimeProfile.new!())
    load_opts = Keyword.get(opts, :load_opts, [])

    with {:ok, registry} <- ModelRegistry.new(models),
         {:ok, profile} <- normalize_profile(profile),
         true <- Keyword.keyword?(load_opts) do
      {:ok, %State{registry: registry, runtime_profile: profile, load_opts: load_opts}}
    else
      false -> {:error, {:invalid_load_opts, load_opts}}
      {:error, _} = error -> error
    end
  end

  @impl true
  def id, do: :system_one_bumblebee

  @impl true
  def capabilities(%State{} = state) do
    model_capabilities =
      state.registry
      |> ModelRegistry.manifests()
      |> Enum.flat_map(& &1.capabilities)
      |> Enum.uniq()

    %{
      protocol: SystemOneContracts.protocol(),
      capabilities: Enum.uniq(Capabilities.core() ++ ["usage:tokens"] ++ model_capabilities)
    }
  end

  @impl true
  def list_models(%State{} = state, _opts) do
    models =
      state.registry
      |> ModelRegistry.manifests()
      |> Enum.map(&ModelManifest.to_contract_model/1)

    {:ok, %ModelsResponse{models: models}}
  end

  @impl true
  def system_one(%State{} = state, %Request{} = request, opts) when is_list(opts) do
    with {:ok, manifest} <- resolve_model(state.registry, request.model),
         :ok <- ModelManifest.supports_request?(manifest, request),
         {:ok, pid} <-
           ServingSupervisor.ensure_started(manifest, state.runtime_profile, state.load_opts),
         canonical_request = %{request | model: manifest.name},
         {:ok, %Response{} = response} <- Serving.run(pid, canonical_request, opts),
         :ok <- response_model(response, manifest.name) do
      {:ok, response}
    else
      {:ok, other} ->
        {:error,
         Error.invalid_response([], "adapter returned the wrong response type", %{value: other})}

      {:error, :model_not_found} ->
        {:error,
         %Error{
           type: :model_not_found,
           message: "System One model not found",
           details: %{model: request.model}
         }}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         %Error{
           type: :internal,
           message: "Native System One inference failed",
           details: %{model: request.model},
           cause: reason
         }}
    end
  end

  def system_one(%State{}, request, _opts),
    do:
      {:error,
       Error.invalid_request([], "expected SystemOneContracts.V1.Request", %{value: request})}

  defp resolve_model(registry, model), do: ModelRegistry.resolve(registry, model)

  defp response_model(%Response{model: model}, model), do: :ok

  defp response_model(%Response{model: actual}, expected) do
    {:error,
     Error.invalid_response(["model"], "adapter returned a different model", %{
       expected: expected,
       actual: actual
     })}
  end

  defp normalize_profile(%RuntimeProfile{} = profile), do: {:ok, profile}
  defp normalize_profile(attrs), do: RuntimeProfile.new(attrs)
end
