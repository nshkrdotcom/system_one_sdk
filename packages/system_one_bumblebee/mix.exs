defmodule SystemOneBumblebee.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/system_one_sdk"
  @package_url @source_url <> "/tree/main/packages/system_one_bumblebee"

  def project do
    [
      app: :system_one_bumblebee,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      name: "SystemOneBumblebee",
      description: "Native BEAM/Nx/Bumblebee implementation of System One inference.",
      source_url: @source_url,
      homepage_url: @package_url,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_deps: :apps_direct, plt_add_apps: [:mix]],
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @package_url},
        files:
          ~w(lib priv README.md CHANGELOG.md LICENSE THIRD_PARTY_NOTICES.md mix.exs guides assets)
      ],
      docs: docs()
    ]
  end

  def application do
    [
      mod: {SystemOneBumblebee.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        credo: :test,
        dialyzer: :test,
        docs: :dev
      ]
    ]
  end

  defp deps do
    [
      # Poncho development dependency. Replace with Hex before publication.
      {:system_one_contracts, path: "../system_one_contracts"},

      # Native model stack. Bumblebee 0.7.1 supports Nx 0.12/0.13 and Axon 0.8.
      {:nx, "~> 0.13.1"},
      {:axon, "~> 0.8.1"},
      {:bumblebee, "~> 0.7.1"},
      {:tokenizers, "~> 0.5.1"},

      # Dependency-prework repositories. These are intentionally local until
      # their prepared releases are published; release_check rejects paths.
      {:hf_hub, path: "../../../../North-Shore-AI/hf_hub_ex"},
      {:crucible_safetensors, path: "../../../../North-Shore-AI/crucible_safetensors"},
      {:jason, "~> 1.4.5"},
      {:telemetry, "~> 1.4.2"},
      {:ex_doc, "~> 0.40.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "docs --warnings-as-errors"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "main",
      source_url_pattern:
        @source_url <> "/blob/main/packages/system_one_bumblebee/%{path}#L%{line}",
      logo: "assets/system_one_bumblebee.svg",
      assets: %{"assets" => "assets"},
      extras: [
        {"README.md", title: "Overview"},
        {"guides/index.md", title: "Guide Index"},
        "guides/architecture.md",
        "guides/model-artifacts.md",
        "guides/runtime.md",
        "guides/laya.md",
        "CHANGELOG.md",
        {"THIRD_PARTY_NOTICES.md", title: "Third-party notices"},
        {"LICENSE", title: "License"}
      ],
      groups_for_modules: [
        "Provider Runtime": [
          SystemOneBumblebee,
          SystemOneBumblebee.Provider,
          SystemOneBumblebee.Serving,
          SystemOneBumblebee.RuntimeProfile
        ],
        "Models and Artifacts": [
          SystemOneBumblebee.ModelAdapter,
          SystemOneBumblebee.ModelManifest,
          SystemOneBumblebee.ModelRegistry,
          SystemOneBumblebee.ArtifactPin,
          SystemOneBumblebee.ArtifactPin.File,
          SystemOneBumblebee.Artifacts,
          SystemOneBumblebee.Artifacts.Prepared,
          SystemOneBumblebee.Models.Laya.Config,
          SystemOneBumblebee.Models.Laya.Preprocessing,
          SystemOneBumblebee.Models.Laya.Calibration,
          SystemOneBumblebee.Models.Laya.Output,
          SystemOneBumblebee.Models.Laya.Inventory,
          SystemOneBumblebee.Models.Laya.Intake
        ],
        Testing: [SystemOneBumblebee.Adapters.Fake]
      ]
    ]
  end
end
