# Answers, Distributions and Explicit Policy

`SystemOneResponse` is the public response. `evaluate` enriches Noul, Choice,
Score and extraction answers. Responses retain `raw`, `unknown_answers`, raw HTTP response, request
ID, model, usage, retry count and elapsed time. Semantic `elapsed_ms` includes
local validation, Pristine execution and decoding; `runtime_elapsed_ms` retains
Pristine's reported timing. Batch responses also carry zero-based `batch_index`.

```elixir
team = SystemOneSDK.Response.fetch!(response, :team)
{:ok, team} = SystemOneSDK.Response.fetch(response, :team)
SystemOneSDK.Response.choices(response)
SystemOneSDK.Response.nouls(response)
SystemOneSDK.Response.scores(response)
SystemOneSDK.Response.values(response)
# => %{urgent: 0.91, team: :billing, severity: 1.7}
```

Fetch uses exact keys, not atom/string coercion. `fetch!` lists available IDs in
its KeyError. Raw/parity responses use strings; semantic responses preserve the
caller key type. Every typed answer retains its own raw payload and ID.
`Response.values/1` projects the primary value of each typed answer and omits
unknown future answer types.

## Text and numeric extraction

With an extraction-capable provider, pass typed field maps to `evaluate/4`.

```elixir
fields = [
  invoice_id: %{type: "text", instructions: "Invoice identifier"},
  total: %{type: "number", instructions: "Invoice total"},
  po_number: %{type: "text", instructions: "Purchase order number"}
]

{:ok, response} =
  SystemOneSDK.evaluate(client, "Invoice INV-7. Total: $0.00.", fields)

SystemOneSDK.Response.values(response)
# => %{invoice_id: "INV-7", total: 0, po_number: nil}

%SystemOneSDK.ExtractionAnswer{span: span, null_probability: p_null} =
  SystemOneSDK.Response.fetch!(response, :invoice_id)
```

An explicit null is a valid answer and appears as `nil`. An omitted answer,
missing `value` key, or mismatched answer type is a response validation error.
An explicit `valid: false` or `complete: false` from the provider also causes a
validation error, including when the provider supplies a null value.
Each answer preserves optional confidence and null probability. `span` contains
the provider's offset pair as an Elixir tuple. Consult the provider for offset
units and source text. Additional fields such as a guess or decoder status are
available on `answer.raw`.

`evaluate/4` decodes extraction values for the requested text and number fields.
Wire-oriented `system_one/4` preserves extraction entries in `unknown_answers`.

## Relational validation

Known answers must match requested IDs and types. Choice selections and the
probability-key domain must match submitted options. Score must lie in the
requested range; legend and probability keys must match level indices. All
probabilities/confidence lie in [0,1]. Distribution sums must be within
`probability_tolerance` (default 0.02, permitted range 0..0.1); values are never
silently renormalized. Tighten to zero when your application requires exact sums
(up to the implementation's floating-point comparison epsilon).

A requested ID missing entirely is an error. An unknown future tag is retained
for decision or open-ended question types. Text and number extraction questions
require a matching tag. Unexpected known IDs fail. Negative or
noninteger usage counts fail; absent optional usage counts remain nil.
A structural/relationally valid answer can still make an incorrect judgment.

## Information helpers

```elixir
SystemOneSDK.Answer.Choice.ranked(team)
SystemOneSDK.Answer.Choice.margin(team)
SystemOneSDK.Answer.confidence(team)

severity = response.answers.severity
SystemOneSDK.Answer.Score.ranked(severity)
SystemOneSDK.Answer.Score.expected_level(severity)
SystemOneSDK.Answer.Score.max_level(severity)
SystemOneSDK.Answer.Score.normalized(severity)
```

Choice ranking is descending; ties follow caller order (deterministic key order
for unenriched legacy answers). Margin is the difference between the top two
probabilities, NOT the provider's confidence. For a Score with probabilities
`%{0 => 0.45, 1 => 0.1, 2 => 0.45}` and expected score 1, the rounded expected
level is 1 but the modal helper returns 0, breaking equal probabilities toward
the lowest index. Normalization divides by the highest legend index; legacy
single-level rubrics return 0.0. Semantic scores retain original rubric labels
and descriptions while preserving the server's legend separately.

Noul has no wire confidence. `Answer.confidence(noul)` derives `max(p, 1-p)`;
that describes certainty, not whether the answer is true or safe to act on.
`Answer.yes?(noul, threshold)` compares probability of true; its convenience
default is 0.5 and is not a recommended risk policy.

## No hidden gate policy

```elixir
case SystemOneSDK.Answer.gate(team, act: 0.90, review: 0.70) do
  :act -> :application_may_continue
  :review -> :request_review
  :escalate -> :use_fallback
end
```

Both thresholds are mandatory, with `0 <= review <= act <= 1`. These numbers are
illustrative. A confident Noul false answer can return `:act`: separately inspect
`yes?` before deciding which business action to perform. Confidence is not a
calibration guarantee. Choose thresholds from task-specific evidence and costs.

Run `mix run examples/live_semantic.exs` for a complete live walkthrough.
See [the live example catalog](../examples/README.md) for setup and API-call costs.
