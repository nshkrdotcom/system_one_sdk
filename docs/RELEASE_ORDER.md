# Release order

1. TypeSafeAPISDK 0.1.0 is already published; retain the SDK's ordinary Hex dependency.
2. Complete contracts/conformance and release system_one_sdk 0.6.0.
3. Complete the native dependency audit and native runtime before releasing system_one_bumblebee 0.1.0.
4. Complete server contracts/runtime before releasing system_one_server 0.1.0.

For each optional package replace the explicit sibling path dependency with
`{:system_one_sdk, "~> 0.6.0"}`, fetch dependencies, and refresh its lockfile.
Run `scripts/release_check PACKAGE` from the root: it rejects path/Git dependencies
and performs a Hex build. No publication is performed by repository scripts.
Run full quality gates and review artifact contents before any actual publication.
