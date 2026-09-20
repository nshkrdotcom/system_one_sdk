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
      name: "SystemOneBumblebee",
      description: "Optional native BEAM/Nx/Bumblebee implementation of System One inference.",
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
          @source_url <> "/blob/main/packages/system_one_bumblebee/%{path}#L%{line}",
        logo: "assets/system_one_bumblebee.svg",
        assets: %{"assets" => "assets"},
        extras: [
          "README.md",
          "guides/index.md",
          "guides/architecture.md",
          "guides/model-artifacts.md",
          "CHANGELOG.md",
          {"LICENSE", title: "License"}
        ]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      # Development only: replace with {:system_one_sdk, "~> 0.6.0"} before release.
      {:system_one_sdk, path: "../system_one_sdk"},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end
end
