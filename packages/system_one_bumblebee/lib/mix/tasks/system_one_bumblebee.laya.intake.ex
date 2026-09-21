defmodule Mix.Tasks.SystemOneBumblebee.Laya.Intake do
  @moduledoc "Generate staged Laya artifact/config/tensor intake evidence."
  @shortdoc "Inspect staged Laya assets"

  use Mix.Task

  alias SystemOneBumblebee.Models.Laya.Intake

  @default_assets Path.expand("~/.cache/laya_ex/hf/convaiinnovations/laya/main")
  @default_output "tmp/laya_intake.json"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {assets, output} =
      case args do
        [] -> {@default_assets, @default_output}
        [assets] -> {Path.expand(assets), @default_output}
        [assets, output] -> {Path.expand(assets), output}
        _ -> Mix.raise("usage: mix system_one_bumblebee.laya.intake [ASSETS_DIR] [OUTPUT_JSON]")
      end

    case Intake.write(assets, output) do
      {:ok, path} ->
        report = Jason.decode!(File.read!(path))
        checkpoint = report["checkpoint"]
        source = report["source"]

        Mix.shell().info("wrote #{path}")
        Mix.shell().info("source revision: #{source["revision"]}")
        Mix.shell().info("checkpoint tensors: #{checkpoint["tensor_inventory"]["tensor_count"]}")
        Mix.shell().info("expected English inventory: #{checkpoint["expected_english_shape"]}")

      {:error, reason} ->
        Mix.raise("Laya intake failed: #{inspect(reason)}")
    end
  end
end
