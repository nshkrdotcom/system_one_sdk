# Model artifacts

Native release models are described by immutable `SystemOneBumblebee.ArtifactPin` values.

A pin contains:

- Hugging Face repository ID and type;
- a full 40-character resolved commit revision;
- every required filename;
- a SHA-256 digest for every required file;
- optional expected SafeTensors tensor metadata.

Mutable names such as `main`, branches and tags are rejected by the runtime pin type. Resolve those names during model intake, record the resulting commit and commit the artifact manifest to source control.

`SystemOneBumblebee.Artifacts.prepare/2` downloads files with `HfHub.Download.hf_hub_download/1` using the immutable revision and expected SHA-256. It then independently verifies the digest with `CrucibleSafetensors.Checksum`. When a tensor manifest is present, `CrucibleSafetensors.Manifest.validate_file/3` validates the SafeTensors header before an adapter constructs or allocates its model graph.

Authentication tokens are runtime load options; they are never persisted in artifact pins.

The Laya adapter will add committed manifests containing the exact upstream code revision, model revision, file hashes and full checkpoint tensor accounting. Python is used only to create parity fixtures and intermediate oracle values, not as the production inference runtime.
