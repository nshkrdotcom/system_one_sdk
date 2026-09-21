defmodule SystemOneBumblebee.Models.Laya.Calibration do
  @moduledoc "Laya temperature scaling, softmax and entropy-derived confidence."

  alias SystemOneBumblebee.Models.Laya.Config

  @spec probabilities([number()], Config.t(), String.t() | atom()) ::
          {:ok, [float()]} | {:error, term()}
  def probabilities(logits, %Config{} = config, type) when is_list(logits) and logits != [] do
    with {:ok, temperature} <- Config.temperature_for(config, type, length(logits)) do
      scaled = Enum.map(logits, &(&1 / temperature))
      max_logit = Enum.max(scaled)
      exps = Enum.map(scaled, &:math.exp(&1 - max_logit))
      total = Enum.sum(exps)
      {:ok, Enum.map(exps, &(&1 / total))}
    end
  end

  def probabilities(logits, _config, type), do: {:error, {:invalid_laya_logits, type, logits}}

  @spec confidence([number()]) :: float()
  def confidence([_one]), do: 1.0

  def confidence(probabilities) when is_list(probabilities) and length(probabilities) >= 2 do
    k = length(probabilities)

    entropy =
      probabilities
      |> Enum.reduce(0.0, fn p, acc ->
        p = max(p * 1.0, 1.0e-12)
        acc - p * :math.log(p)
      end)

    clamp(1.0 - entropy / :math.log(k), 0.0, 1.0)
  end

  @spec features([number()]) :: [float()]
  def features(probabilities) when is_list(probabilities) and length(probabilities) >= 2 do
    [top1, top2 | _] = probabilities |> Enum.sort(:desc)
    k = length(probabilities)

    entropy =
      probabilities
      |> Enum.reduce(0.0, fn p, acc ->
        p = max(p * 1.0, 1.0e-9)
        acc - p * :math.log(p)
      end)
      |> Kernel./(:math.log(k))

    [top1 * 1.0, (top1 - top2) * 1.0, entropy * 1.0, k / 255.0]
  end

  defp clamp(value, low, _high) when value < low, do: low
  defp clamp(value, _low, high) when value > high, do: high
  defp clamp(value, _low, _high), do: value
end
