# Package matrix

| Directory under packages/ | OTP app | Public module | Development version | Runtime dependency |
| --- | --- | --- | --- | --- |
| system_one_contracts | :system_one_contracts | SystemOneContracts | 0.1.0 | jason ~> 1.4.5 |
| system_one_sdk | :system_one_sdk | SystemOneSDK | 0.6.0 | sibling system_one_contracts (development), typesafe_api_sdk ~> 0.1.0, pristine ~> 0.4.0, jason ~> 1.4.5, telemetry ~> 1.3 |
| system_one_bumblebee | :system_one_bumblebee | SystemOneBumblebee | 0.1.0 | sibling system_one_contracts (development only) |
| system_one_server | :system_one_server | SystemOneServer | 0.1.0 | sibling system_one_contracts (development only) |

SystemOneSDK 0.5.0 and TypeSafeAPISDK 0.1.0 are published. The contracts package
and optional runtime/server packages are not yet published. Every package is an
independent Mix project. ML and HTTP server stacks remain deferred to their
respective implementation phases.

Publish `system_one_contracts` first, then replace sibling path dependencies with
`{:system_one_contracts, "~> 0.1.0"}` before publishing dependents.
