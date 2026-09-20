defmodule Mix.Tasks.Typesafe.Ir do
  use Mix.Task
  @moduledoc false
  @shortdoc "Prints the compiled SystemOneSDK ProviderIR"
  @impl true
  def run(args), do: Mix.Task.run("pristine.codegen.ir", ["SystemOneSDK.Codegen.Provider" | args])
end
