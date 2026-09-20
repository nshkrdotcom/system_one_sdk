# Architecture

This package depends on SystemOneSDK; the SDK never depends on this package.
It will own network exposure, HTTP validation, authentication and service operations. Shared provider-neutral contracts and conformance
belong in SystemOneSDK. No standalone contracts package is planned.

Next: `GET /v1/models`, `POST /v1/systemone`, health/readiness, auth, validation, telemetry, request IDs and resource limits; first a fake provider, then native integration.
