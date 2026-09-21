defmodule SystemOneBumblebee.ServingSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias SystemOneBumblebee.{ModelManifest, RuntimeProfile, Serving}

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec ensure_started(ModelManifest.t(), RuntimeProfile.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_started(%ModelManifest{} = manifest, %RuntimeProfile{} = profile, load_opts \\ []) do
    case Registry.lookup(SystemOneBumblebee.ServingRegistry, manifest.name) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        child = {Serving, manifest: manifest, profile: profile, load_opts: load_opts}

        case DynamicSupervisor.start_child(__MODULE__, child) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, {:already_present, _id}} -> lookup(manifest.name)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec stop_model(String.t()) :: :ok | {:error, :not_found}
  def stop_model(name) when is_binary(name) do
    case Registry.lookup(SystemOneBumblebee.ServingRegistry, name) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  defp lookup(name) do
    case Registry.lookup(SystemOneBumblebee.ServingRegistry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :serving_start_race}
    end
  end
end
