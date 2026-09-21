defmodule SystemOneBumblebee.ModelRegistry do
  @moduledoc "Immutable registry of explicitly configured native System One models and aliases."

  alias SystemOneBumblebee.ModelManifest

  @enforce_keys [:models, :aliases]
  defstruct models: %{}, aliases: %{}

  @type t :: %__MODULE__{
          models: %{String.t() => ModelManifest.t()},
          aliases: %{String.t() => String.t()}
        }

  @spec new(map() | [ModelManifest.t()]) :: {:ok, t()} | {:error, term()}
  def new(models \\ %{})

  def new(models) when is_map(models) do
    models
    |> Enum.sort_by(fn {name, _attrs} -> to_string(name) end)
    |> Enum.reduce_while({:ok, []}, fn {name, attrs}, {:ok, acc} ->
      case ModelManifest.new(to_string(name), attrs) do
        {:ok, manifest} -> {:cont, {:ok, [manifest | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> build(Enum.reverse(reversed))
      error -> error
    end
  end

  def new(models) when is_list(models) do
    if Enum.all?(models, &match?(%ModelManifest{}, &1)),
      do: build(models),
      else: {:error, {:invalid_model_registry, models}}
  end

  def new(other), do: {:error, {:invalid_model_registry, other}}

  @spec resolve(t(), String.t()) :: {:ok, ModelManifest.t()} | {:error, :model_not_found}
  def resolve(%__MODULE__{} = registry, name) when is_binary(name) do
    canonical = Map.get(registry.aliases, name, name)

    case Map.fetch(registry.models, canonical) do
      {:ok, manifest} -> {:ok, manifest}
      :error -> {:error, :model_not_found}
    end
  end

  @spec manifests(t()) :: [ModelManifest.t()]
  def manifests(%__MODULE__{models: models}) do
    models |> Map.values() |> Enum.sort_by(& &1.name)
  end

  defp build(manifests) do
    Enum.reduce_while(
      manifests,
      {:ok, %__MODULE__{models: %{}, aliases: %{}}},
      &put_manifest/2
    )
  end

  defp put_manifest(manifest, {:ok, registry}) do
    case model_name_available(registry, manifest.name) do
      :ok -> put_manifest_with_aliases(registry, manifest)
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp model_name_available(registry, name) do
    cond do
      Map.has_key?(registry.models, name) -> {:error, {:duplicate_model, name}}
      Map.has_key?(registry.aliases, name) -> {:error, {:model_conflicts_with_alias, name}}
      true -> :ok
    end
  end

  defp put_manifest_with_aliases(%__MODULE__{} = registry, manifest) do
    case put_aliases(registry, manifest) do
      {:ok, aliases} ->
        updated = %__MODULE__{
          registry
          | models: Map.put(registry.models, manifest.name, manifest),
            aliases: aliases
        }

        {:cont, {:ok, updated}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp put_aliases(registry, manifest) do
    Enum.reduce_while(manifest.aliases, {:ok, registry.aliases}, fn alias_name, {:ok, aliases} ->
      cond do
        Map.has_key?(registry.models, alias_name) ->
          {:halt, {:error, {:alias_conflicts_with_model, alias_name}}}

        Map.has_key?(aliases, alias_name) ->
          {:halt, {:error, {:duplicate_alias, alias_name}}}

        true ->
          {:cont, {:ok, Map.put(aliases, alias_name, manifest.name)}}
      end
    end)
  end
end
