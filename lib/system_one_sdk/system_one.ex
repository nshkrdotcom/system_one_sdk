defmodule SystemOneSDK.SystemOne do
  @moduledoc "Provider-neutral raw System One API surface."

  alias SystemOneSDK.{
    Client,
    Question,
    RequestBudget,
    SystemOneResponse
  }

  @spec run(Client.t(), term(), map(), keyword()) ::
          {:ok, SystemOneResponse.t()} | {:error, term()}
  def run(%Client{} = client, state, questions, opts \\ [])
      when is_map(questions) and is_list(opts) do
    with {:ok, normalized_questions} <- Question.normalize_questions(questions) do
      body = %{
        "state" => state,
        "model" => Keyword.get(opts, :model) || client.default_model,
        "questions" => normalized_questions
      }

      body =
        Map.merge(
          body,
          normalize_extra_body(Keyword.get(opts, :extra_body, %{}))
        )

      max_bytes = RequestBudget.effective(client.max_request_bytes, opts)

      with :ok <- RequestBudget.validate(max_bytes, ["options", "max_request_bytes"]),
           :ok <- RequestBudget.check(body, max_bytes) do
        Client.system_one(client, state, normalized_questions, opts)
      end
    end
  end

  defp normalize_extra_body(nil), do: %{}

  defp normalize_extra_body(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_extra_body(other) do
    raise ArgumentError, "extra_body must be a map, got: #{inspect(other)}"
  end
end
