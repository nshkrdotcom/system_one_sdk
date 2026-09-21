defmodule SystemOneContracts.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/system_one_sdk"
  @package_url @source_url <> "/tree/main/packages/system_one_contracts"

  def project do
    [
      app: :system_one_contracts,
      version: @version,
      elixir: "~> 1.18",
      name: "SystemOneContracts",
      description:
        "Provider-neutral System One v1 wire contracts and inference provider behaviour.",
      source_url: @source_url,
      homepage_url: @package_url,
      deps: deps(),
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @package_url},
        maintainers: ["nshkrdotcom"],
        files: ~w(lib README.md CHANGELOG.md LICENSE mix.exs guides)
      ],
      docs: [
        main: "readme",
        source_ref: "main",
        source_url_pattern:
          @source_url <> "/blob/main/packages/system_one_contracts/%{path}#L%{line}",
        extras: [
          "README.md",
          "guides/protocol.md",
          "guides/providers.md",
          "CHANGELOG.md",
          {"LICENSE", title: "License"}
        ],
        groups_for_modules: [
          "Protocol v1": ~r/^SystemOneContracts\.V1\./,
          "Provider contracts": [
            SystemOneContracts.Provider,
            SystemOneContracts.Capabilities,
            SystemOneContracts.Conformance
          ],
          Errors: [SystemOneContracts.Error]
        ]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:jason, "~> 1.4.5"},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end
end
