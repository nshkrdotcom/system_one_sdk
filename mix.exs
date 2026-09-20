if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule SystemOneSDK.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/nshkrdotcom/system_one_sdk"

  def project do
    [
      app: :system_one_sdk,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      name: "SystemOneSDK",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix, :pristine]]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      workspace_dep({:pristine, "~> 0.4.0"}),
      workspace_dep({:typesafe_api_sdk, "~> 0.1.0"}),
      {:jason, "~> 1.4.5"},
      {:telemetry, "~> 1.3"},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
    |> List.flatten()
  end

  defp workspace_dep(committed) do
    if Code.ensure_loaded?(MixWorkspaceOpsBootstrap) and
         function_exported?(MixWorkspaceOpsBootstrap, :dep, 2) do
      apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__])
    else
      committed
    end
  end

  defp description do
    "Provider-neutral Elixir SDK for System One semantics, evaluation, batching, telemetry, and OTP integration."
  end

  defp package do
    [
      name: "system_one_sdk",
      description: description(),
      files: ~w(lib guides cheatsheets examples README.md CHANGELOG.md LICENSE mix.exs assets),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["nshkrdotcom"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      canonical: "https://hexdocs.pm/system_one_sdk",
      logo: "assets/system_one_sdk.svg",
      assets: %{"assets" => "assets"},
      extras: [
        {"README.md", title: "Overview"},
        {"guides/index.md", title: "Guide Index", filename: "guide-index"},
        "guides/getting-started.md",
        {"examples/README.md", title: "Live Example Catalog", filename: "live-example"},
        "guides/client-configuration.md",
        "guides/system-one-and-questions.md",
        "guides/models.md",
        "guides/errors-and-retries.md",
        "guides/semantic-questions.md",
        "guides/answers-and-confidence.md",
        "guides/batching.md",
        "guides/testing.md",
        "guides/telemetry.md",
        "guides/runtime-capabilities.md",
        "guides/runtime-controls.md",
        "guides/confidence-routing.md",
        "guides/composite-scoring.md",
        "guides/speculative-fan-out.md",
        "guides/recursive-decisions.md",
        "guides/otp-server.md",
        "guides/evaluating-decisions.md",
        {"examples/evaluation/README.md",
         title: "Decision Evaluation Workflow", filename: "decision-evaluation"},
        "cheatsheets/system_one_sdk.cheatmd",
        "CHANGELOG.md",
        {"LICENSE", title: "License", filename: "license"}
      ],
      groups_for_extras: [
        "Start Here": ["README.md", "guides/index.md", "guides/getting-started.md"],
        Usage: [
          "guides/client-configuration.md",
          "guides/system-one-and-questions.md",
          "guides/models.md",
          "guides/errors-and-retries.md"
        ],
        "Semantic API": [
          "guides/semantic-questions.md",
          "guides/answers-and-confidence.md",
          "guides/batching.md",
          "guides/testing.md"
        ],
        Operations: [
          "guides/telemetry.md",
          "guides/runtime-capabilities.md",
          "guides/runtime-controls.md"
        ],
        Patterns: [
          "guides/confidence-routing.md",
          "guides/composite-scoring.md",
          "guides/speculative-fan-out.md",
          "guides/recursive-decisions.md",
          "guides/otp-server.md",
          "guides/evaluating-decisions.md"
        ],
        Examples: [
          "examples/README.md",
          "examples/evaluation/README.md",
          "cheatsheets/system_one_sdk.cheatmd"
        ],
        Project: ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "Semantic Questions": [
          SystemOneSDK.Question.Noul,
          SystemOneSDK.Question.Choice,
          SystemOneSDK.Question.Score,
          SystemOneSDK.Prepared
        ],
        "Semantic Helpers": [
          SystemOneSDK.Response,
          SystemOneSDK.Answer,
          SystemOneSDK.Answer.Noul,
          SystemOneSDK.Answer.Choice,
          SystemOneSDK.Answer.Score
        ],
        "Batch and Observability": [
          SystemOneSDK.Batch,
          SystemOneSDK.Telemetry,
          SystemOneSDK.RuntimeCapabilities,
          SystemOneSDK.OTP.Server
        ],
        "Testing and Contracts": [
          SystemOneSDK.Test,
          SystemOneSDK.Test.ContractError,
          SystemOneSDK.Schema
        ],
        "Client and Operations": [
          SystemOneSDK,
          SystemOneSDK.Client,
          SystemOneSDK.SystemOne,
          SystemOneSDK.Models
        ],
        Questions: [
          SystemOneSDK.Noul,
          SystemOneSDK.NoulCriteria,
          SystemOneSDK.Choice,
          SystemOneSDK.Score,
          SystemOneSDK.Question
        ],
        Responses: [
          SystemOneSDK.SystemOneResponse,
          SystemOneSDK.ListModelsResponse,
          SystemOneSDK.ModelMetadata,
          SystemOneSDK.NoulAnswer,
          SystemOneSDK.ChoiceAnswer,
          SystemOneSDK.ScoreAnswer,
          SystemOneSDK.Usage
        ],
        "Errors and Configuration": [
          SystemOneSDK.Error,
          SystemOneSDK.RetryPolicy,
          SystemOneSDK.Constants
        ],
        "Generated API": ~r/^SystemOneSDK\.Generated\./,
        "Runtime Integration": ~r/^SystemOneSDK\.(ProviderProfile|ResultClassifier|Transport)/,
        "Maintenance Tasks": ~r/^Mix\.Tasks\.Typesafe\./
      ]
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "cmd env MIX_ENV=test mix test --warnings-as-errors",
        "credo --strict",
        "reach.check --arch --smells",
        "dialyzer",
        "docs --warnings-as-errors",
        "typesafe.verify"
      ]
    ]
  end
end
