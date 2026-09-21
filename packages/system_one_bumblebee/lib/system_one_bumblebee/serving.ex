defmodule SystemOneBumblebee.Serving do
  @moduledoc """
  Resident adapter runtime for one registered model.

  Loading is serialized once in the process `init/1`. Inference itself executes
  outside the GenServer after a fast snapshot of immutable runtime state, so the
  wrapper does not force all calls for a model through a single mailbox.
  """

  use GenServer

  alias SystemOneBumblebee.{Artifacts, ModelManifest, RuntimeProfile}
  alias SystemOneContracts.V1.Request

  @type snapshot :: %{
          adapter: module(),
          runtime: term(),
          manifest: ModelManifest.t(),
          profile: RuntimeProfile.t()
        }

  def start_link(opts) do
    manifest = Keyword.fetch!(opts, :manifest)
    GenServer.start_link(__MODULE__, opts, name: via(manifest.name))
  end

  @impl true
  def init(opts) do
    manifest = Keyword.fetch!(opts, :manifest)
    profile = Keyword.fetch!(opts, :profile)
    load_opts = Keyword.get(opts, :load_opts, [])

    with {:ok, artifacts} <- Artifacts.prepare(manifest.pin, load_opts),
         {:ok, runtime} <-
           manifest.adapter.load(manifest, artifacts, profile, manifest.adapter_options) do
      {:ok,
       %{
         adapter: manifest.adapter,
         runtime: runtime,
         manifest: manifest,
         profile: profile
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @spec run(pid(), Request.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def run(pid, %Request{} = request, opts \\ []) when is_pid(pid) and is_list(opts) do
    with {:ok, snapshot} <- snapshot(pid) do
      metadata = %{
        model: snapshot.manifest.name,
        adapter: snapshot.adapter,
        runtime_profile: snapshot.profile.name
      }

      :telemetry.span([:system_one_bumblebee, :inference], metadata, fn ->
        result = snapshot.adapter.infer(snapshot.runtime, request, opts)
        {result, metadata}
      end)
    end
  end

  @spec snapshot(pid()) :: {:ok, snapshot()} | {:error, term()}
  def snapshot(pid) when is_pid(pid) do
    {:ok, GenServer.call(pid, :snapshot)}
  catch
    :exit, reason -> {:error, {:serving_unavailable, reason}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @spec via(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via(name), do: {:via, Registry, {SystemOneBumblebee.ServingRegistry, name}}
end
