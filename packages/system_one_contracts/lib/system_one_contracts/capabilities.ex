defmodule SystemOneContracts.Capabilities do
  @moduledoc "Stable semantic capability vocabulary for System One v1 providers and models."

  @question_noul "question:noul"
  @question_choice "question:choice"
  @question_score "question:score"
  @ordered_choice "choice:ordered"
  @models_list "models:list"
  @usage_tokens "usage:tokens"
  @request_id "request:id"
  @cancellation "request:cancellation"
  @batch "request:batch"
  @streaming "request:streaming"

  @known [
    @question_noul,
    @question_choice,
    @question_score,
    @ordered_choice,
    @models_list,
    @usage_tokens,
    @request_id,
    @cancellation,
    @batch,
    @streaming
  ]

  @spec known() :: [String.t()]
  def known, do: @known

  @spec core() :: [String.t()]
  def core do
    [
      @question_noul,
      @question_choice,
      @question_score,
      @ordered_choice,
      @models_list
    ]
  end

  @spec normalize(term()) :: {:ok, [String.t()]} | {:error, SystemOneContracts.Error.t()}
  def normalize(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_name(value) do
        {:ok, name} -> {:cont, {:ok, [name | acc]}}
        :error -> {:halt, invalid()}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, reversed |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  def normalize(_), do: invalid()

  defp normalize_name(value) when is_atom(value), do: normalize_name(Atom.to_string(value))

  defp normalize_name(value) when is_binary(value) do
    name = String.trim(value)
    if name == "", do: :error, else: {:ok, name}
  end

  defp normalize_name(_), do: :error

  defp invalid do
    {:error,
     SystemOneContracts.Error.invalid_request(
       ["capabilities"],
       "must be a list of nonblank capability names"
     )}
  end
end
