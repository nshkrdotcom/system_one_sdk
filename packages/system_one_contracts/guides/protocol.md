# System One v1 protocol

The protocol identifier is `system-one/v1`.

`SystemOneContracts.V1.Request` stores questions as an ordered list of `{name,
question}` entries. Maps are accepted for convenience but are sorted by wire key;
callers that care about semantic choice order should pass pair lists or already
ordered Jason values inside each question.

HTTP servers should pass the **raw JSON body** to `Request.decode_json/1`. It uses
Jason's ordered-object decoding so Choice criteria retain their source order.
Once an ordinary map decoder has discarded object order, the original Choice
ordering cannot be reconstructed reliably.

The wire request has three canonical fields:

- `state`
- `model`
- `questions`

Additional top-level fields are allowed through the request's `extra` map but may
not replace canonical fields.

Responses contain `model`, `usage`, and `answers`. Known Noul, Choice and Score
answers receive structural validation. Unknown future answer types are preserved
so clients can remain forward-compatible while explicitly deciding how to handle
them.
