defmodule SystemOneBumblebee.Models.Laya.Config do
  @moduledoc """
  Parsed Laya runtime configuration from `rl_agent_config.json`.

  The type mapping and calibration layout mirror upstream Laya 0.3.3. Runtime
  code consumes the artifact values rather than replacing them with local
  defaults.
  """

  @enforce_keys [
    :encoder,
    :head_layers,
    :max_len,
    :head_max_len,
    :max_prefixes,
    :amp_dtype,
    :temperature,
    :temperature_by_options
  ]
  defstruct @enforce_keys ++ [:model_name, :act_costs]

  @type t :: %__MODULE__{
          encoder: String.t(),
          head_layers: non_neg_integer(),
          max_len: pos_integer(),
          head_max_len: pos_integer(),
          max_prefixes: pos_integer(),
          amp_dtype: String.t(),
          temperature: [number()],
          temperature_by_options: %{String.t() => number()},
          model_name: String.t() | nil,
          act_costs: map()
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) when is_binary(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, json} <- Jason.decode(bytes) do
      decode(json)
    end
  end

  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(json) when is_map(json) do
    with {:ok, encoder} <- nonblank(json["encoder"], :encoder),
         {:ok, head_layers} <- non_negative(json["head_layers"], :head_layers),
         {:ok, max_len} <- positive(json["max_len"], :max_len),
         {:ok, head_max_len} <- positive(json["head_max_len"], :head_max_len),
         true <- head_max_len < max_len,
         {:ok, max_prefixes} <- positive(json["max_prefixes"], :max_prefixes),
         {:ok, amp_dtype} <- amp_dtype(json["amp_dtype"]),
         {:ok, temperature} <- temperatures(json["temperature"]),
         {:ok, temperature_by_options} <- temperature_map(json["temperature_by_options"] || %{}),
         {:ok, act_costs} <- map(json["act_costs"] || %{}, :act_costs),
         {:ok, model_name} <- optional_string(json["model_name"], :model_name) do
      {:ok,
       %__MODULE__{
         encoder: encoder,
         head_layers: head_layers,
         max_len: max_len,
         head_max_len: head_max_len,
         max_prefixes: max_prefixes,
         amp_dtype: amp_dtype,
         temperature: temperature,
         temperature_by_options: temperature_by_options,
         model_name: model_name,
         act_costs: act_costs
       }}
    else
      false -> {:error, {:invalid_laya_config, :head_max_len_must_be_less_than_max_len}}
      {:error, _} = error -> error
    end
  end

  def decode(other), do: {:error, {:invalid_laya_config, other}}

  @spec qtype_index(String.t() | atom()) :: {:ok, 0 | 1 | 2} | {:error, term()}
  def qtype_index(type) when type in ["choice", :choice], do: {:ok, 0}
  def qtype_index(type) when type in ["score", :score], do: {:ok, 1}
  def qtype_index(type) when type in ["noul", :noul], do: {:ok, 2}
  def qtype_index(type), do: {:error, {:unsupported_laya_question_type, type}}

  @spec temperature_bucket(String.t() | atom(), pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def temperature_bucket(type, option_count) when is_integer(option_count) and option_count > 0 do
    with {:ok, _index} <- qtype_index(type) do
      name = if is_atom(type), do: Atom.to_string(type), else: type

      suffix =
        cond do
          option_count <= 2 -> "2"
          option_count <= 5 -> "3-5"
          option_count <= 10 -> "6-10"
          true -> "11+"
        end

      {:ok, "#{name}:#{suffix}"}
    end
  end

  def temperature_bucket(type, option_count),
    do: {:error, {:invalid_temperature_bucket, type, option_count}}

  @spec temperature_for(t(), String.t() | atom(), pos_integer()) ::
          {:ok, float()} | {:error, term()}
  def temperature_for(%__MODULE__{} = config, type, option_count) do
    with {:ok, index} <- qtype_index(type),
         {:ok, bucket} <- temperature_bucket(type, option_count),
         fallback when is_number(fallback) <- Enum.at(config.temperature, index) do
      value = Map.get(config.temperature_by_options, bucket, fallback)
      {:ok, max(0.001, value * 1.0)}
    else
      nil -> {:error, {:missing_base_temperature, type}}
      {:error, _} = error -> error
    end
  end

  defp temperatures(values) when is_list(values) and length(values) >= 3 do
    if Enum.all?(values, &(is_number(&1) and &1 > 0)),
      do: {:ok, values},
      else: {:error, {:invalid_laya_config, :temperature}}
  end

  defp temperatures(_), do: {:error, {:invalid_laya_config, :temperature}}

  defp temperature_map(values) when is_map(values) do
    if Enum.all?(values, fn {key, value} -> is_binary(key) and is_number(value) and value > 0 end),
       do: {:ok, values},
       else: {:error, {:invalid_laya_config, :temperature_by_options}}
  end

  defp temperature_map(_), do: {:error, {:invalid_laya_config, :temperature_by_options}}

  defp amp_dtype(value) when value in ["bf16", "fp16", "f16", "float16"], do: {:ok, value}
  defp amp_dtype(value), do: {:error, {:invalid_laya_config, {:amp_dtype, value}}}

  defp map(value, _field) when is_map(value), do: {:ok, value}
  defp map(value, field), do: {:error, {:invalid_laya_config, {field, value}}}

  defp positive(value, _field) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(value, field), do: {:error, {:invalid_laya_config, {field, value}}}

  defp non_negative(value, _field) when is_integer(value) and value >= 0, do: {:ok, value}
  defp non_negative(value, field), do: {:error, {:invalid_laya_config, {field, value}}}

  defp nonblank(value, _field) when is_binary(value) and value != "", do: {:ok, value}
  defp nonblank(value, field), do: {:error, {:invalid_laya_config, {field, value}}}

  defp optional_string(nil, _field), do: {:ok, nil}
  defp optional_string(value, _field) when is_binary(value), do: {:ok, value}
  defp optional_string(value, field), do: {:error, {:invalid_laya_config, {field, value}}}
end
