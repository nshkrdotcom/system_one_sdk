defmodule SystemOneContracts.V1.Request do
  @moduledoc "Canonical provider-neutral System One v1 request with ordered question entries."

  alias SystemOneContracts.Error
  alias SystemOneContracts.V1.Validation

  @canonical ~w(state model questions)

  @enforce_keys [:state, :model, :questions]
  defstruct [:state, :model, :questions, extra: %{}]

  @type question_entry :: {String.t(), map()}
  @type t :: %__MODULE__{
          state: term(),
          model: String.t(),
          questions: [question_entry()],
          extra: map()
        }

  @spec new(term(), map() | list() | Jason.OrderedObject.t(), String.t(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def new(state, questions, model, opts \\ []) when is_list(opts) do
    with {:ok, model} <- model(model),
         :ok <- Validation.json(state, ["state"]),
         {:ok, questions} <- normalize_questions(questions),
         {:ok, extra} <- normalize_extra(Keyword.get(opts, :extra, %{})) do
      {:ok, %__MODULE__{state: state, model: model, questions: questions, extra: extra}}
    end
  end

  @spec new!(term(), map() | list() | Jason.OrderedObject.t(), String.t(), keyword()) :: t()
  def new!(state, questions, model, opts \\ []) do
    case new(state, questions, model, opts) do
      {:ok, request} -> request
      {:error, error} -> raise error
    end
  end

  @doc """
  Decode an already-parsed request object.

  Ordering already lost by an ordinary map cannot be recovered.
  """
  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(%Jason.OrderedObject{values: values}), do: decode_pairs(values)

  def decode(body) when is_map(body) and not is_struct(body) do
    body
    |> Map.to_list()
    |> decode_pairs()
  end

  def decode(_), do: {:error, Error.invalid_request([], "request must be a JSON object")}

  @doc "Decode raw JSON while preserving object order, including Choice criteria order."
  @spec decode_json(iodata()) :: {:ok, t()} | {:error, Error.t()}
  def decode_json(json) do
    case Jason.decode(json, objects: :ordered_objects) do
      {:ok, body} -> decode(body)
      {:error, error} -> {:error, Error.invalid_request([], "invalid JSON", %{cause: error})}
    end
  rescue
    error -> {:error, Error.invalid_request([], "invalid JSON", %{cause: error})}
  end

  @spec question_keys(t()) :: [String.t()]
  def question_keys(%__MODULE__{questions: questions}), do: Enum.map(questions, &elem(&1, 0))

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = request) do
    request.extra
    |> Map.put("state", request.state)
    |> Map.put("model", request.model)
    |> Map.put("questions", Jason.OrderedObject.new(request.questions))
  end

  @spec encode(t()) :: {:ok, binary()} | {:error, Jason.EncodeError.t()}
  def encode(%__MODULE__{} = request), do: Jason.encode(to_map(request))

  @spec encode!(t()) :: binary()
  def encode!(%__MODULE__{} = request), do: Jason.encode!(to_map(request))

  defp decode_pairs(pairs) do
    with {:ok, pairs} <- normalize_object_pairs(pairs, []),
         {:ok, state} <- required_pair(pairs, "state"),
         {:ok, model} <- required_pair(pairs, "model"),
         {:ok, questions} <- required_pair(pairs, "questions") do
      extra =
        pairs
        |> Enum.reject(fn {key, _value} -> key in @canonical end)
        |> Map.new()

      new(state, questions, model, extra: extra)
    end
  end

  defp required_pair(pairs, key) do
    case List.keyfind(pairs, key, 0) do
      {^key, value} -> {:ok, value}
      nil -> {:error, Error.invalid_request([key], "is required")}
    end
  end

  defp model(value) do
    case Validation.nonblank_string(value, ["model"]) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, Error.invalid_request(["model"], "must be a nonblank UTF-8 string")}
    end
  end

  defp normalize_questions(%Jason.OrderedObject{values: pairs}),
    do: normalize_question_pairs(pairs)

  defp normalize_questions(questions) when is_map(questions) and not is_struct(questions) do
    with {:ok, normalized} <- normalize_question_pairs(Map.to_list(questions)) do
      {:ok, Enum.sort_by(normalized, &elem(&1, 0))}
    end
  end

  defp normalize_questions(questions) when is_list(questions),
    do: normalize_question_pairs(questions)

  defp normalize_questions(_),
    do: {:error, Error.invalid_request(["questions"], "must be a map or ordered key/value list")}

  defp normalize_question_pairs([]),
    do: {:error, Error.invalid_request(["questions"], "must contain at least one question")}

  defp normalize_question_pairs(pairs) do
    with {:ok, pairs} <- normalize_object_pairs(pairs, ["questions"]) do
      Enum.reduce_while(pairs, {:ok, []}, fn {wire_key, question}, {:ok, acc} ->
        case normalize_question(question, wire_key) do
          {:ok, normalized} -> {:cont, {:ok, [{wire_key, normalized} | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
        error -> error
      end
    end
  rescue
    Protocol.UndefinedError ->
      {:error, Error.invalid_request(["questions"], "must be a proper key/value list")}
  end

  defp normalize_question(question, key) when is_map(question) do
    type = Validation.value(question, "type")

    with {:ok, _type} <- required_type(type, key),
         :ok <- Validation.json(question, ["questions", key]) do
      {:ok, question}
    end
  end

  defp normalize_question(_question, key),
    do: {:error, Error.invalid_request(["questions", key], "must be a JSON object")}

  defp required_type(value, key) do
    case Validation.nonblank_string(value, ["questions", key, "type"]) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, Error.invalid_request(["questions", key, "type"], "must be nonblank")}
    end
  end

  defp normalize_extra(nil), do: {:ok, %{}}

  defp normalize_extra(extra) when is_map(extra) and not is_struct(extra) do
    with {:ok, extra} <- Validation.string_key_map(extra, ["extra"]),
         nil <- Enum.find(@canonical, &Map.has_key?(extra, &1)),
         :ok <- Validation.json(extra, ["extra"]) do
      {:ok, extra}
    else
      field when is_binary(field) ->
        {:error, Error.invalid_request(["extra", field], "cannot override a canonical field")}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_extra(_),
    do: {:error, Error.invalid_request(["extra"], "must be a JSON object")}

  defp normalize_object_pairs(pairs, path) when is_list(pairs) do
    Enum.reduce_while(pairs, {:ok, [], MapSet.new()}, fn
      {key, value}, {:ok, acc, seen} when is_binary(key) or is_atom(key) ->
        wire_key = to_string(key)

        cond do
          String.trim(wire_key) == "" or not String.valid?(wire_key) ->
            {:halt, {:error, Error.invalid_request(path, "contains an invalid object key")}}

          MapSet.member?(seen, wire_key) ->
            {:halt,
             {:error, Error.invalid_request(path ++ [wire_key], "duplicate normalized key")}}

          true ->
            {:cont, {:ok, [{wire_key, value} | acc], MapSet.put(seen, wire_key)}}
        end

      _entry, _acc ->
        {:halt, {:error, Error.invalid_request(path, "expected key/value pairs")}}
    end)
    |> case do
      {:ok, reversed, _seen} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp normalize_object_pairs(_pairs, path),
    do: {:error, Error.invalid_request(path, "expected key/value pairs")}
end
