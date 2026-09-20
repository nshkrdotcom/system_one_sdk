defmodule SystemOneSDK.ReleaseConsistencyTest do
  use ExUnit.Case, async: true

  test "SystemOneSDK release identity is internally consistent" do
    assert SystemOneSDK.version() == "0.6.0"
    assert Mix.Project.config()[:version] == "0.6.0"
    assert Mix.Project.config()[:app] == :system_one_sdk
    assert Mix.Project.config()[:docs][:source_ref] == "main"

    assert Mix.Project.config()[:source_url] ==
             "https://github.com/nshkrdotcom/system_one_sdk"
  end

  test "default provider is the TypeSafe adapter backed by TypeSafeAPISDK" do
    client =
      SystemOneSDK.new_client(
        api_key: "test-key",
        retry: false
      )

    assert client.provider == SystemOneSDK.Providers.TypeSafe
    assert %TypeSafeAPISDK.Client{} = client.provider_client
  end

  test "registered documentation and package identity assets exist" do
    docs = Mix.Project.config()[:docs]

    for entry <- docs[:extras] do
      path = if is_tuple(entry), do: elem(entry, 0), else: entry
      assert File.regular?(path), "missing documentation: #{path}"
    end

    for path <- [
          "LICENSE",
          "assets/system_one_sdk.svg",
          "guides",
          "cheatsheets",
          "examples/evaluation",
          ".reach.exs"
        ] do
      assert File.exists?(path), "missing package asset: #{path}"
    end
  end
end
