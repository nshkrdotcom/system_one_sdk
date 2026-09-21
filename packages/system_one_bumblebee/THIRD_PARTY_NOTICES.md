# Third-party notices

## Laya

SystemOneBumblebee contains an independent Elixir/Nx port of model-runtime logic derived from the
open-source Laya project by Convai Innovations and contributors.

- Project: `NandhaKishorM/laya`
- Reference version: 0.3.3
- Reference code revision: `6a5819129eb220570792e417e49723d697efd76f`
- English checkpoint: `convaiinnovations/laya`
- Pinned checkpoint revision: `c5d78730f3493e4fe16d61507ef4b78eef7318cf`
- License: Apache-2.0

The SystemOneBumblebee package as a whole remains MIT licensed. Laya-derived runtime behavior and
model artifacts remain subject to their upstream Apache-2.0 terms. Model weights are not bundled in
this repository or Hex package.

## ModernBERT / Bumblebee

The English Laya checkpoint uses `answerdotai/ModernBERT-large`. SystemOneBumblebee uses upstream
Bumblebee/Nx/Axon for the encoder implementation rather than copying ModernBERT source into this
package. Their respective licenses and notices continue to apply.
