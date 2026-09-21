defmodule SystemOneServer.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/system_one_sdk"
  @package_url @source_url <> "/tree/main/packages/system_one_server"

  def project do
    [
      app: :system_one_server,
      version: @version,
      elixir: "~> 1.18",
      name: "SystemOneServer",
      description: "Optional HTTP/network façade for the System One v1 protocol.",
      source_url: @source_url,
      homepage_url: @package_url,
      deps: deps(),
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @package_url},
        files: ~w(lib README.md CHANGELOG.md LICENSE mix.exs guides assets)
      ],
      docs: [
        main: "readme",
        source_ref: "main",
        source_url_pattern:
          @source_url <> "/blob/main/packages/system_one_server/%{path}#L%{line}",
        logo: "assets/system_one_server.svg",
        assets: %{"assets" => "assets"},
        extras: [
          "README.md",
          "guides/index.md",
          "guides/architecture.md",
          "guides/deployment.md",
          "CHANGELOG.md",
          {"LICENSE", title: "License"}
        ]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      # Development only: replace with {:system_one_contracts, "~> 0.1.0"} before release.
      {:system_one_contracts, path: "../system_one_contracts"},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end
end
