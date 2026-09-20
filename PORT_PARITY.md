# Python 0.6.0 -> Elixir 0.2.0 parity map

This file is a handoff index, not an additional runtime specification. The
supplied Python `system-one-sdk` 0.6.0 repository remains the semantic oracle for
this initial port.

| Python surface | Elixir surface | Ownership |
| --- | --- | --- |
| `TypeSafeClient(...)` / `AsyncTypeSafeClient(...)` | `SystemOneSDK.Client.new/1` | handwritten provider facade |
| `.system_one(...)` | `SystemOneSDK.system_one/4`, `SystemOneSDK.SystemOne.run/4` | handwritten ergonomic facade over generated operation |
| `.models.list(...)` | `SystemOneSDK.list_models/2`, `SystemOneSDK.Models.list/2` | handwritten ergonomic facade over generated operation |
| `Noul` | `SystemOneSDK.Noul` | handwritten public type |
| `NoulCriteria` | `SystemOneSDK.NoulCriteria.t()` | handwritten public type contract |
| `Choice` | `SystemOneSDK.Choice` | handwritten public type |
| `Score` | `SystemOneSDK.Score` | handwritten public type |
| `NoulAnswer` | `SystemOneSDK.NoulAnswer` | handwritten public type |
| `ChoiceAnswer` | `SystemOneSDK.ChoiceAnswer` | handwritten public type |
| `ScoreAnswer` | `SystemOneSDK.ScoreAnswer` | handwritten public type |
| `Usage` | `SystemOneSDK.Usage` | handwritten public token-count type; live wire schema also omits `billing_units` |
| `ModelMetadata` | `SystemOneSDK.ModelMetadata` | handwritten public type |
| `SystemOneResponse` | `SystemOneSDK.SystemOneResponse` | handwritten decoder + response metadata |
| `ListModelsResponse` | `SystemOneSDK.ListModelsResponse` | handwritten decoder + response metadata |
| `RetryPolicy` | `SystemOneSDK.RetryPolicy` | handwritten provider policy |
| TypeSafe exception hierarchy | `%SystemOneSDK.Error{type: ...}` | idiomatic single Elixir exception/result type |
| generated Python wire models | `SystemOneSDK.Generated.*` | PristineCodegen-owned, generated and verified |
| Python OpenAPI generator URL | `priv/upstream/openapi.json` + `SystemOneSDK.Codegen.Source.OpenAPI` | committed deterministic source + bounded refresh |

## Intentional language/runtime adaptations

Elixir has one immutable client value rather than duplicated synchronous and
asynchronous client classes. Callers get concurrency from processes/Tasks.
Network APIs return `{:ok, value}` / `{:error, %SystemOneSDK.Error{}}` rather
than raising for ordinary API failures.

Question maps remain forward-compatible. Unknown future answer tags are logged
and skipped while known malformed answer types fail with a precise field path.
Successful responses retain the TypeSafe request ID and raw `Pristine.Response`
metadata separately from the decoded public payload.

## Runtime prerequisite

Retry parity uses the locally completed contract in `PREREQUISITE_PRISTINE_0.3.0.md`.
Do not replace that prerequisite with 100 exact 5xx overrides. The completed
Pristine 0.3.0 provider profile supports an inclusive `500..599` range with
exact-status precedence, verified through the real classifier and SDK pipeline.

## 0.2.0 semantic additions above parity

The table above describes the preserved wire-oriented system_one/list_models
surface. Strict Question.* constructors, prepare/evaluate, caller identity,
relational validation, enriched answers, batch execution, application fixtures,
semantic telemetry, schema export and decision evaluation are provider-owned
Elixir additions. The underlying generated operations and Pristine execution
path are unchanged. In particular, protected `extra_body` behavior applies to
strict evaluate only; legacy system_one retains last-write-wins overrides.

Known probability ranges, nonnegative usage and normalized-key collision checks
are stronger than the old shallow decoder. Unknown future answer types still
skip typed decoding and are now retained explicitly in raw/unknown_answers.
The strict semantic level/option limits are not retroactively attributed to
Python 0.6.0 or the committed OpenAPI wire schema. See guides/migration-0.2.md.

## 0.3.0 runtime and semantic additions

0.3.0 preserves the wire/parity surface above while moving the runtime prerequisite
to Pristine `~> 0.4.0`. The earlier `PREREQUISITE_PRISTINE_0.3.0.md` remains a
historical record of the status-range work used by 0.2; it is not the current
runtime target.

The 0.3 semantic layer adds direct `Pristine.Cancellation` forwarding,
Pristine-owned capability discovery, structural retry-policy inheritance,
Prepared composition/fingerprints, opt-in strict response contracts, local
serialized-request byte budgets, pure model catalog helpers, and stable bounded
metadata. None of these additions creates a TypeSafe HTTP stack, retry engine,
transport cancellation implementation, global queue, or circuit breaker.
## 0.4.0 OTP/observability additions

0.4.0 does not change the two-operation wire/parity surface or generated OpenAPI
contracts. `Response.values/1` is a projection of existing enriched answer
structs; per-answer telemetry is emitted only after the existing semantic
validation path; and `SystemOneSDK.OTP.Server` calls the same `Evaluation.run/4`
path under a caller-owned TaskSupervisor. The OTP facade adds no transport,
retry, serialization, auth, generated model, or provider operation of its own.
