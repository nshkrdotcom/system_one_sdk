defmodule SystemOneSDK.Generated.Schemas.SystemOneResponse do
  @moduledoc """
  Generated Typesafe Sdk type module `SystemOneSDK.Generated.Schemas.SystemOneResponse`.
  """

  alias SystemOneSDK.Generated.RuntimeSchema, as: RuntimeSchema

  @enforce_keys [:answers, :model, :usage]
  defstruct [:answers, :model, :usage]

  @type t :: %__MODULE__{
          answers: term(),
          model: String.t(),
          usage: SystemOneSDK.Generated.Schemas.Usage.t()
        }
  @doc false
  @spec __fields__(atom()) :: keyword()
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      answers:
        {:map, :string,
         {:union,
          [
            {SystemOneSDK.Generated.Schemas.NoulAnswer, :t},
            {SystemOneSDK.Generated.Schemas.ScoreAnswer, :t},
            {SystemOneSDK.Generated.Schemas.ChoiceAnswer, :t}
          ]}},
      model: :string,
      usage: {SystemOneSDK.Generated.Schemas.Usage, :t}
    ]
  end

  @doc false
  @spec __openapi_fields__(atom()) :: [map()]
  def __openapi_fields__(type \\ :t)

  def __openapi_fields__(:t) do
    [
      %{
        description:
          "Answers keyed by the question names supplied in the request. Each answer's type matches its question's type.",
        name: "answers",
        nullable: false,
        required: true,
        type:
          {:map, :string,
           {:union,
            [
              {SystemOneSDK.Generated.Schemas.NoulAnswer, :t},
              {SystemOneSDK.Generated.Schemas.ScoreAnswer, :t},
              {SystemOneSDK.Generated.Schemas.ChoiceAnswer, :t}
            ]}}
      },
      %{
        description:
          "Name of the model that answered the questions. May differ from the alias supplied in the request.",
        name: "model",
        nullable: false,
        required: true,
        type: :string
      },
      %{
        description: "Input and output token counts for this evaluation.",
        name: "usage",
        nullable: false,
        required: true,
        type: {SystemOneSDK.Generated.Schemas.Usage, :t}
      }
    ]
  end

  @doc false
  @spec __schema__(atom()) :: Sinter.Schema.t()
  def __schema__(type \\ :t) when is_atom(type) do
    RuntimeSchema.build_schema(__openapi_fields__(type))
  end

  @doc false
  @spec decode(map(), atom()) :: {:ok, term()} | {:error, term()}
  def decode(data, type \\ :t)

  def decode(data, type) when is_map(data) and is_atom(type) do
    RuntimeSchema.decode_module_type(__MODULE__, type, data)
  end
end
