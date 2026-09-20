defmodule Mix.Tasks.Typesafe.Verify do
  use Mix.Task
  @moduledoc false
  @shortdoc "Verifies committed SystemOneSDK generated artifacts"
  @impl true
  def run(args),
    do: Mix.Task.run("pristine.codegen.verify", ["SystemOneSDK.Codegen.Provider" | args])
end
