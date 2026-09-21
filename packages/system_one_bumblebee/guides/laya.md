# Laya native adapter

The first native System One architecture is Laya, using the English `convaiinnovations/laya`
checkpoint and upstream Bumblebee ModernBERT.

The reference checkpoint is pinned to `c5d78730f3493e4fe16d61507ef4b78eef7318cf`; the reviewed
Python 0.3.3 source baseline is `6a5819129eb220570792e417e49723d697efd76f`. These identities are
recorded in `priv/models/laya/source.json` and third-party attribution is in
`THIRD_PARTY_NOTICES.md`.

This phase ports and tests the deterministic parts before model math:

- exact question type mapping (`choice=0`, `score=1`, `noul=2`);
- Python-compatible state, criterion and option rendering;
- mask-token sanitization;
- head/option budget arithmetic;
- option-count temperature buckets and artifact calibration values;
- probability, entropy-confidence and action-feature formulas;
- final System One answer translation;
- staged checkpoint SHA-256 and SafeTensors inventory reporting.

Generate local intake evidence from the already-staged checkpoint:

```bash
mix system_one_bumblebee.laya.intake   ~/.cache/laya_ex/hf/convaiinnovations/laya/main   tmp/laya_intake.json
```

The command hashes every staged file and records the SafeTensors tensor inventory without copying
weights into the repository. The expected English checkpoint has 206 tensors, including 170
`encoder.*`, one `type_emb.*`, six `scorer.*` and four `act_head.*` tensors.

The next adapter layer uses Bumblebee ModernBERT for encoder hidden states, then maps the pinned
custom Laya decision-head tensors into Axon/Nx and checks stage-by-stage parity against the locked
Python oracle. Python remains validation tooling only; production inference stays in BEAM/Nx.
