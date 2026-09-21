# Architecture

This package depends only on `system_one_contracts` at the System One boundary;
it does not depend on the rich `system_one_sdk` package. It will own network
exposure, HTTP validation, authentication, service operations and translation
between HTTP v1 DTOs and a configured `SystemOneContracts.Provider`.

That keeps the server usable with native or third-party inference providers
without pulling client-side evaluation, batching, OTP helpers or TypeSafe HTTP
code into the service.

Next: `GET /v1/models`, `POST /v1/systemone`, health/readiness, auth, validation,
telemetry, request IDs and resource limits; first a fake provider, then native
integration.
