defmodule MixWorkspaceOpsBootstrap do
  @moduledoc false

  def dep(committed, project_root) do
    case elem(committed, 0) do
      :typesafe_api_sdk ->
        local = typesafe_api_sdk_path(project_root)

        if File.dir?(local) do
          opts =
            if tuple_size(committed) == 3,
              do: elem(committed, 2),
              else: []

          {:typesafe_api_sdk,
           Keyword.merge(opts,
             path: local,
             override: true
           )}
        else
          committed
        end

      _ ->
        committed
    end
  end

  defp typesafe_api_sdk_path(project_root) do
    case System.get_env("TYPESAFE_API_SDK_PATH") do
      nil ->
        Path.expand("../typesafe_api_sdk", project_root)

      value ->
        case String.trim(value) do
          "" -> Path.expand("../typesafe_api_sdk", project_root)
          path -> Path.expand(path, project_root)
        end
    end
  end
end
