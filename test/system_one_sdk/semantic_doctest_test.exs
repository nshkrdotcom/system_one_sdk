defmodule SystemOneSDK.SemanticDoctestTest do
  use ExUnit.Case, async: true
  doctest SystemOneSDK.Question.Noul
  doctest SystemOneSDK.Question.Choice
  doctest SystemOneSDK.Question.Score
end
