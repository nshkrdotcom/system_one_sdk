defmodule SystemOneBumblebee.RuntimeProfile do
  @moduledoc """
  Explicit model execution profile.

  The package never selects an accelerator from OS environment variables.
  Applications pass backend/compiler choices here. EXLA is therefore usable by
  a host application without becoming a required dependency of this package.
  """

  @enforce_keys [:name]
  defstruct name: :default,
            backend: nil,
            compiler: nil,
            type: nil,
            batch_size: 1,
            sequence_length: nil,
            defn_options: [],
            serving_options: []

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          backend: term(),
          compiler: term(),
          type: atom() | nil,
          batch_size: pos_integer(),
          sequence_length: pos_integer() | nil,
          defn_options: keyword(),
          serving_options: keyword()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    with {:ok, name} <- name(value(attrs, :name, :default)),
         {:ok, batch_size} <- positive(value(attrs, :batch_size, 1), :batch_size),
         {:ok, sequence_length} <- optional_positive(value(attrs, :sequence_length), :sequence_length),
         {:ok, defn_options} <- keyword(value(attrs, :defn_options, []), :defn_options),
         {:ok, serving_options} <- keyword(value(attrs, :serving_options, []), :serving_options) do
      {:ok,
       %__MODULE__{
         name: name,
         backend: value(attrs, :backend),
         compiler: value(attrs, :compiler),
         type: value(attrs, :type),
         batch_size: batch_size,
         sequence_length: sequence_length,
         defn_options: defn_options,
         serving_options: serving_options
       }}
    end
  end

  @spec new!(keyword() | map()) :: t()
  def new!(attrs \\ []) do
    case new(attrs) do
      {:ok, profile} -> profile
      {:error, reason} -> raise ArgumentError, "invalid runtime profile: #{inspect(reason)}"
    end
  end

  @spec test() :: t()
  def test, do: new!(name: :test, type: :f32)

  @spec cpu() :: t()
  def cpu, do: new!(name: :cpu, backend: Nx.BinaryBackend, type: :f32)

  defp name(value) when is_atom(value), do: {:ok, value}
  defp name(value) when is_binary(value) and value != "", do: {:ok, value}
  defp name(value), do: {:error, {:invalid_profile_name, value}}

  defp positive(value, _key) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(value, key), do: {:error, {key, value}}

  defp optional_positive(nil, _key), do: {:ok, nil}
  defp optional_positive(value, key), do: positive(value, key)

  defp keyword(value, _key) when is_list(value) do
    if Keyword.keyword?(value), do: {:ok, value}, else: {:error, {:not_keyword, value}}
  end

  defp keyword(value, key), do: {:error, {key, value}}

  defp value(attrs, key, default \\ nil)
  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
