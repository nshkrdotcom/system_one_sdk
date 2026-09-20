defmodule Mix.Tasks.Typesafe.Generate do
  use Mix.Task
  @moduledoc false
  @shortdoc "Generates committed SystemOneSDK artifacts from the OpenAPI snapshot"
  @impl true
  def run(args),
    do: Mix.Task.run("pristine.codegen.generate", ["SystemOneSDK.Codegen.Provider" | args])
end
