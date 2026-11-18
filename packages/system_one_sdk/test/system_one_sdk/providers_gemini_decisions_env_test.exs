defmodule SystemOneSDK.Providers.GeminiDecisionsEnvTest do
  use ExUnit.Case, async: false

  alias SystemOneSDK.Error
  alias SystemOneSDK.Providers.GeminiDecisions

  @env_vars [
    "LITELLM_BASE_URL",
    "LITELLM_API_KEY",
    "GEMINI_DECISIONS_BASE_URL",
    "GEMINI_API_KEY"
  ]

  setup do
    previous = Map.new(@env_vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, val} -> System.put_env(key, val)
      end)
    end)

    :ok
  end

  test "raises on missing LITELLM_BASE_URL in unified mode" do
    System.delete_env("LITELLM_BASE_URL")

    assert_raise Error, ~r/Missing :base_url/, fn ->
      GeminiDecisions.new_client(decisions_mode: :unified)
    end
  end

  test "falls back symmetrically to LITELLM_API_KEY and GEMINI_API_KEY unless suppressed" do
    System.put_env("LITELLM_BASE_URL", "http://litellm.env.invalid")
    System.put_env("LITELLM_API_KEY", "env-litellm-key")
    System.put_env("GEMINI_API_KEY", "env-gemini-key")

    unified = GeminiDecisions.new_client(decisions_mode: :unified)
    assert unified.base_url == "http://litellm.env.invalid"
    assert unified.api_key == "env-litellm-key"

    suppressed = GeminiDecisions.new_client(decisions_mode: :unified, api_key: false)
    assert suppressed.api_key == nil

    native = GeminiDecisions.new_client(decisions_mode: :native)
    assert native.api_key == "env-gemini-key"

    native_explicit =
      GeminiDecisions.new_client(decisions_mode: :native, gemini_api_key: "explicit-gemini-key")

    assert native_explicit.api_key == "explicit-gemini-key"
  end
end
