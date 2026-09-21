defmodule SystemOneContracts.V1.Validation do
  @moduledoc false

  alias SystemOneContracts.Error

  def nonblank_string(value, _path) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "" or not String.valid?(trimmed), do: :error, else: {:ok, trimmed}
  end

  def nonblank_string(_value, _path), do: :error

  def probability(value) when is_number(value) and value >= 0 and value <= 1, do: :ok
  def probability(_), do: :error

  def json(value, path) do
    case Jason.encode(value) do
      {:ok, _} -> :ok
      {:error, reason} ->
        {:error, Error.invalid_request(path, "must be JSON-encodable", %{cause: reason})}
    end
  rescue
    error -> {:error, Error.invalid_request(path, "must be JSON-encodable", %{cause: error})}
  end

  def string_key_map(value, path) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn
      {key, item}, {:ok, acc} when is_binary(key) or is_atom(key) ->
        key = to_string(key)

        cond do
          String.trim(key) == "" or not String.valid?(key) ->
            {:halt, {:error, Error.invalid_request(path, "contains an invalid key")}}

          Map.has_key?(acc, key) ->
            {:halt, {:error, Error.invalid_request(path ++ [key], "duplicate normalized key")}}

          true ->
            {:cont, {:ok, Map.put(acc, key, item)}}
        end

      _entry, _acc ->
        {:halt, {:error, Error.invalid_request(path, "keys must be strings or atoms")}}
    end)
  end

  def string_key_map(_value, path),
    do: {:error, Error.invalid_request(path, "must be a JSON object")}

  def value(%Jason.OrderedObject{values: values}, key) do
    case List.keyfind(values, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  def value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, known_atom(key))
    end
  end

  def known_atom("state"), do: :state
  def known_atom("model"), do: :model
  def known_atom("questions"), do: :questions
  def known_atom("usage"), do: :usage
  def known_atom("answers"), do: :answers
  def known_atom("models"), do: :models
  def known_atom("name"), do: :name
  def known_atom("description"), do: :description
  def known_atom("release_date"), do: :release_date
  def known_atom("capabilities"), do: :capabilities
  def known_atom("metadata"), do: :metadata
  def known_atom("input_tokens"), do: :input_tokens
  def known_atom("output_tokens"), do: :output_tokens
  def known_atom("type"), do: :type
  def known_atom("noul"), do: :noul
  def known_atom("choice"), do: :choice
  def known_atom("confidence"), do: :confidence
  def known_atom("probabilities"), do: :probabilities
  def known_atom("score"), do: :score
  def known_atom("legend"), do: :legend
  def known_atom(_), do: :__system_one_contracts_missing_key__
end
