defmodule SystemOneBumblebee.Models.Laya.Inventory do
  @moduledoc "SafeTensors metadata inventory for the pinned Laya checkpoint."

  alias CrucibleSafetensors.{Manifest, Reader}

  @spec analyze(Path.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) when is_binary(path) do
    with {:ok, header} <- Reader.open(path) do
      inventory = Manifest.inventory(header)
      {:ok, summarize(inventory)}
    end
  end

  @spec summarize([map()]) :: map()
  def summarize(inventory) when is_list(inventory) do
    families =
      inventory
      |> Enum.group_by(fn tensor -> family(tensor.name) end)
      |> Map.new(fn {family, tensors} -> {family, length(tensors)} end)

    dtypes =
      inventory
      |> Enum.group_by(& &1.dtype)
      |> Map.new(fn {dtype, tensors} -> {to_string(dtype), length(tensors)} end)

    %{
      tensor_count: length(inventory),
      families: families,
      dtypes: dtypes,
      tensors: inventory
    }
  end

  @spec expected_english_shape?(map()) :: boolean()
  def expected_english_shape?(%{tensor_count: 206, families: families}) do
    Map.get(families, :encoder, 0) == 170 and
      Map.get(families, :type_emb, 0) == 1 and
      Map.get(families, :scorer, 0) == 6 and
      Map.get(families, :act_head, 0) == 4
  end

  def expected_english_shape?(_), do: false

  defp family("encoder." <> _), do: :encoder
  defp family("type_emb." <> _), do: :type_emb
  defp family("scorer." <> _), do: :scorer
  defp family("act_head." <> _), do: :act_head
  defp family("head." <> _), do: :decision_head
  defp family(_), do: :other
end
