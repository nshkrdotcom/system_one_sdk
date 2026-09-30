# Contracts and SDK release implementation plan

> **For agentic workers:** Execute inline using superpowers:executing-plans. Publication, commits, pushes and plain version tags are explicitly authorized by the user.

**Goal:** Publish system_one_contracts 0.1.0 and system_one_sdk 0.6.0, then update and verify Fount against Hex dependencies.

**Architecture:** Four independent Poncho packages; contracts is the shared protocol package, the SDK is the rich client. Optional native/server packages stay outside these releases.

**Tech Stack:** Elixir, Mix, Hex, ExDoc, Credo, Dialyzer.

**Spec:** User release instructions dated 2026-09-29 in this session.

## Global Constraints

- Release date 2026-09-29; MIT Copyright (c) 2026 nshkrdotcom.
- SDK release manifest must use system_one_contracts ~> 0.1.0 from Hex.
- Commit and push release sources before publishing; publish contracts then SDK; tag only after publication.
- Offline tests only; inspect package allowlists and built archive contents.
- Preserve Fount workspace sibling dependencies; update external Hex requirements and locks.

## Review Focus

- Exclude credentials, model weights, build directories and large generated artifacts from Hex archives.
- Verify all guides, changelog and license appear in ExDoc navigation.
- Verify SDK against actual published contracts before SDK publication.
- Ensure plain v0.1.0 and v0.6.0 tags identify the exact published sources.
- Run Fount QC without the local SDK override.

## Tasks

- [x] Prepare manifests, dated changelogs, README status and AGENTS.md. Add contracts docs navigation and static analysis tools; pin source links to release tags.
- [ ] Run contracts dependencies, format, warnings-as-errors compile/tests, Credo, Dialyzer and docs. Rehearse SDK QC with local contracts before publication, inspect both built archives, and commit/push release sources with SDK Hex requirement.
- [ ] Publish contracts, resolve SDK from Hex, rerun SDK QC and release build; commit/push its resolved lockfile before SDK publication.
- [ ] Publish SDK, verify Hex release versions, tag corresponding commits and push tags.
- [ ] Query latest stable external Fount dependencies, update manifests/locks, run format/compile/tests and workspace QC, fix findings, commit and push Fount.

## Execution record

- Initial repositories clean; SDK branch fount-phase1-sdk, Fount branch main.
- Hex API: contracts absent, SDK 0.5.0, Inference 0.5.1, AgentSessionManager 0.17.3.
- Ruling: release preparation runs in the existing clean checkouts because the user explicitly requested commits and pushes in these repositories.
- Ruling: SDK prepublication QC uses the existing local contracts dependency; final SDK QC resolves published contracts from Hex. Contracts does not yet exist on Hex, so these phases are necessarily sequential.

- Contracts QC passed: 6 tests, strict Credo clean, Dialyzer 0 errors, warning-free ExDoc.
- SDK rehearsal passed: 1 doctest + 140 tests, 2 live tests excluded, strict Credo clean, Dialyzer 0 errors, warning-free ExDoc; Mint upgraded to 1.11.0.
- Both Hex builds pass with explicit allowlists; inspected contracts 16,384 bytes and SDK 135,680 bytes, no secrets/builds/model artifacts.
