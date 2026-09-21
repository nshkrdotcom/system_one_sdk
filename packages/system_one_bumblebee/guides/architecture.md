# Architecture

SystemOneBumblebee depends only on `system_one_contracts` at the System One boundary; it does not depend on the rich `system_one_sdk` package. Applications that want the rich SDK bridge this provider through `SystemOneSDK.Providers.Contract`.

```text
SystemOneContracts.Provider
          ^
          |
SystemOneBumblebee.Provider
          |
          +--> ModelRegistry --> ModelManifest --> ArtifactPin
          |
          +--> ServingSupervisor --> Serving --> ModelAdapter
                                      |
                                      +--> Laya (next)
                                      +--> other native adapters

Artifacts --> HfHub.Download
          --> CrucibleSafetensors checksum/manifest validation
```

The registry accepts only explicitly configured model IDs and aliases. Requests cannot select arbitrary Hugging Face repositories.

`Serving` loads and retains one adapter runtime per canonical model. The GenServer owns initialization/state lifetime, but inference runs outside its mailbox after a fast immutable snapshot so the wrapper does not serialize all calls.

EXLA is not a required dependency. Runtime profiles carry backend/compiler choices explicitly from the host application. No library runtime module chooses an accelerator from OS environment variables.

HTTP belongs in `system_one_server`. Process/container lifecycle belongs in `self_hosted_inference_core`.
