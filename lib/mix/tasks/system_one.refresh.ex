defmodule Mix.Tasks.Typesafe.Refresh do
  use Mix.Task
  @moduledoc false
  @shortdoc "Fetches the upstream OpenAPI document and regenerates SystemOneSDK"
  @impl true
  def run(args),
    do: Mix.Task.run("pristine.codegen.refresh", ["SystemOneSDK.Codegen.Provider" | args])
end
