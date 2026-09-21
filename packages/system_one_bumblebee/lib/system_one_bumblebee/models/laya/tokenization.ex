defmodule SystemOneBumblebee.Models.Laya.Tokenization do
  @moduledoc """
  Exact Laya tokenizer and sequence construction.

  This module ports the inference-time sequence layout from upstream Laya:

      [CLS]
      <qtype> question: <instructions>
      [SEP]
      [MASK] option 0
      [MASK] option 1
      ...
      [SEP]
      state
      [SEP]

  It deliberately operates on explicit token IDs rather than relying on a
  tokenizer post-processor, because Laya records marker positions before the
  option token sequences are appended.
  """

  alias SystemOneBumblebee.Models.Laya.Preprocessing
  alias Tokenizers.Encoding
  alias Tokenizers.Tokenizer, as: NativeTokenizer

  @special_tokens [
    cls: "[CLS]",
    sep: "[SEP]",
    pad: "[PAD]",
    mask: "[MASK]",
    unk: "[UNK]"
  ]

  @enforce_keys [:native, :special_ids]
  defstruct [:native, :special_ids]

  @type t :: %__MODULE__{
          native: NativeTokenizer.t(),
          special_ids: %{
            required(:cls) => non_neg_integer(),
            required(:sep) => non_neg_integer(),
            required(:pad) => non_neg_integer(),
            required(:mask) => non_neg_integer(),
            required(:unk) => non_neg_integer()
          }
        }

  @type sequence :: %{
          required(:input_ids) => [non_neg_integer()],
          required(:attention_mask) => [0 | 1],
          required(:marker_positions) => [non_neg_integer()],
          required(:marker_mask) => [boolean()],
          required(:qtype) => 0 | 1 | 2,
          required(:rendered_question) => String.t(),
          required(:rendered_options) => [String.t()],
          required(:serialized_state) => String.t(),
          required(:head_token_count) => non_neg_integer(),
          required(:option_token_counts) => [non_neg_integer()],
          required(:state_token_count) => non_neg_integer()
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(assets_directory) when is_binary(assets_directory) do
    tokenizer_path =
      Path.join([
        Path.expand(assets_directory),
        "tokenizer",
        "tokenizer.json"
      ])

    with true <- File.regular?(tokenizer_path),
         {:ok, native} <- NativeTokenizer.from_file(tokenizer_path),
         {:ok, special_ids} <- resolve_special_ids(native) do
      {:ok, %__MODULE__{native: native, special_ids: special_ids}}
    else
      false ->
        {:error, {:missing_laya_tokenizer, tokenizer_path}}

      {:error, _} = error ->
        error
    end
  end

  @spec build_sequence(t(), term(), map(), keyword()) ::
          {:ok, sequence()} | {:error, term()}
  def build_sequence(%__MODULE__{} = tokenizer, state, question, opts \\ []) do
    max_len = Keyword.get(opts, :max_len, 512)
    head_max_len = Keyword.get(opts, :head_max_len, 192)
    option_order = Keyword.get(opts, :option_order)
    truncate_left = Keyword.get(opts, :truncate_left, false)

    with :ok <- validate_lengths(max_len, head_max_len),
         {:ok, rendered_question} <- Preprocessing.render_question(question),
         {:ok, rendered_options} <- Preprocessing.render_options(question),
         :ok <- ensure_options(rendered_options),
         {:ok, ordered_options} <- order_options(rendered_options, option_order),
         {:ok, serialized_state} <- Preprocessing.serialize_state(state),
         {:ok, qtype} <- Preprocessing.qtype(question),
         {:ok, head_ids} <- encode_ids(tokenizer, rendered_question),
         {:ok, raw_option_ids} <- encode_options(tokenizer, ordered_options),
         {:ok, option_ids, head_budget} <-
           Preprocessing.rebudget_option_ids(raw_option_ids, head_max_len),
         {:ok, state_ids} <-
           encode_ids(tokenizer, Preprocessing.sanitize_mask(serialized_state)) do
      head_ids = Enum.take(head_ids, max(8, head_budget))

      {prefix_ids, marker_positions} =
        append_options(
          [tokenizer.special_ids.cls] ++
            head_ids ++
            [tokenizer.special_ids.sep],
          option_ids
        )

      prefix_ids = prefix_ids ++ [tokenizer.special_ids.sep]

      room = max(0, max_len - length(prefix_ids) - 1)

      state_ids =
        if truncate_left do
          take_right(state_ids, room)
        else
          Enum.take(state_ids, room)
        end

      input_ids =
        (prefix_ids ++ state_ids ++ [tokenizer.special_ids.sep])
        |> Enum.take(max_len)

      marker_positions =
        Enum.filter(marker_positions, &(&1 < max_len))

      {:ok,
       %{
         input_ids: input_ids,
         attention_mask: List.duplicate(1, length(input_ids)),
         marker_positions: marker_positions,
         marker_mask: List.duplicate(true, length(marker_positions)),
         qtype: qtype,
         rendered_question: rendered_question,
         rendered_options: ordered_options,
         serialized_state: serialized_state,
         head_token_count: length(head_ids),
         option_token_counts: Enum.map(option_ids, &length/1),
         state_token_count: length(state_ids)
       }}
    end
  end

  @spec special_ids(t()) :: map()
  def special_ids(%__MODULE__{special_ids: special_ids}), do: special_ids

  defp resolve_special_ids(native) do
    Enum.reduce_while(@special_tokens, {:ok, %{}}, fn {name, token}, {:ok, acc} ->
      case NativeTokenizer.token_to_id(native, token) do
        id when is_integer(id) and id >= 0 ->
          {:cont, {:ok, Map.put(acc, name, id)}}

        nil ->
          {:halt, {:error, {:missing_laya_special_token, name, token}}}
      end
    end)
  end

  defp encode_options(tokenizer, options) do
    Enum.reduce_while(options, {:ok, []}, fn option, {:ok, acc} ->
      option = " " <> Preprocessing.sanitize_mask(option)

      case encode_ids(tokenizer, option) do
        {:ok, ids} ->
          ids =
            [tokenizer.special_ids.mask] ++
              Enum.take(ids, 48)

          {:cont, {:ok, [ids | acc]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> reverse_ok()
  end

  defp encode_ids(%__MODULE__{native: native}, text) when is_binary(text) do
    case NativeTokenizer.encode(native, text, add_special_tokens: false) do
      {:ok, encoding} ->
        {:ok, Encoding.get_ids(encoding)}

      {:error, reason} ->
        {:error, {:laya_tokenization_failed, reason}}
    end
  end

  defp append_options(initial_ids, option_ids) do
    Enum.reduce(option_ids, {initial_ids, []}, fn ids, {acc, markers} ->
      marker = length(acc)
      {acc ++ ids, markers ++ [marker]}
    end)
  end

  defp order_options(options, nil), do: {:ok, options}

  defp order_options(options, order) when is_list(order) do
    expected =
      case length(options) do
        0 -> []
        count -> Enum.to_list(0..(count - 1))
      end

    if Enum.sort(order) == expected do
      {:ok, Enum.map(order, &Enum.at(options, &1))}
    else
      {:error, {:invalid_laya_option_order, order, length(options)}}
    end
  end

  defp order_options(options, order),
    do: {:error, {:invalid_laya_option_order, order, length(options)}}

  defp validate_lengths(max_len, head_max_len)
       when is_integer(max_len) and
              is_integer(head_max_len) and
              max_len > 0 and
              head_max_len > 0 and
              head_max_len < max_len,
       do: :ok

  defp validate_lengths(max_len, head_max_len),
    do: {:error, {:invalid_laya_sequence_lengths, max_len, head_max_len}}

  defp ensure_options([_ | _]), do: :ok
  defp ensure_options([]), do: {:error, :laya_question_has_no_options}

  defp take_right(_values, 0), do: []
  defp take_right(values, count), do: Enum.take(values, -count)

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error
end
