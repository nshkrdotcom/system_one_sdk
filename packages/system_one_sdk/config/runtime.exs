import Config

blank_to_nil = fn
  nil ->
    nil

  value ->
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
end

if api_key = blank_to_nil.(System.get_env("TYPESAFE_API_KEY")) do
  config :system_one_sdk, api_key: api_key
end

if base_url = blank_to_nil.(System.get_env("TYPESAFE_BASE_URL")) do
  config :system_one_sdk, base_url: String.trim_trailing(base_url, "/")
end

if model = blank_to_nil.(System.get_env("TYPESAFE_DEFAULT_MODEL")) do
  config :system_one_sdk, default_model: model
end

if level = blank_to_nil.(System.get_env("TYPESAFE_LOG_LEVEL")) do
  case String.downcase(level) do
    "debug" -> config :system_one_sdk, log_level: :debug
    "info" -> config :system_one_sdk, log_level: :info
    "warning" -> config :system_one_sdk, log_level: :warn
    "warn" -> config :system_one_sdk, log_level: :warn
    "error" -> config :system_one_sdk, log_level: :error
    _ -> :ok
  end
end
