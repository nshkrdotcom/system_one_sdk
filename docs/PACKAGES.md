# Package matrix

| Directory under packages/ | OTP app | Public module | Development version | Runtime dependency |
| --- | --- | --- | --- | --- |
| system_one_sdk | :system_one_sdk | SystemOneSDK | 0.6.0 | typesafe_api_sdk ~> 0.1.0, pristine ~> 0.4.0, jason ~> 1.4.5, telemetry ~> 1.3 |
| system_one_bumblebee | :system_one_bumblebee | SystemOneBumblebee | 0.1.0 | sibling system_one_sdk (development only) |
| system_one_server | :system_one_server | SystemOneServer | 0.1.0 | sibling system_one_sdk (development only) |

SDK 0.5.0 and TypeSafeAPISDK 0.1.0 are published. New packages are scaffolds,
not published runtimes. All packages have their own lockfile and MIT LICENSE.
The optional packages use ExDoc for development; ML and HTTP stacks are deferred.
Before publication replace sibling dependencies with system_one_sdk ~> 0.6.0.
