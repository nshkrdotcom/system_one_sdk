# Release order

1. TypeSafeAPISDK 0.1.0 is already published; retain the SDK's ordinary Hex dependency.
2. Complete and publish `system_one_contracts` 0.1.0.
3. Replace the SDK's contracts path dependency with `{:system_one_contracts, "~> 0.1.0"}`, complete QC, and release `system_one_sdk` 0.6.0.
4. Complete the native dependency audit/runtime before releasing `system_one_bumblebee` 0.1.0.
5. Complete server runtime before releasing `system_one_server` 0.1.0.

Before publishing each dependent package, replace its explicit sibling contracts
path with the Hex requirement, fetch dependencies, and refresh its lockfile.
Run `scripts/release_check PACKAGE` from the root: it rejects path/Git
dependencies and performs a Hex build. No publication is performed by repository
scripts. Run full quality gates and review artifact contents before publication.
