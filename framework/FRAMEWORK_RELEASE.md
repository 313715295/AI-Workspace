# Framework release process

This root-owned process governs Framework release work across versions. It is not part of a sealed version payload, a consumer runtime rule pack, a project task or a second authority. The Maintenance control repository supplies the current task, authorization, Review and evidence; this file supplies the reusable release sequence.

## Release classification

- `ROOT_MAINTENANCE`: bounded repository-level documentation, license, checkout policy, release procedure or integration tooling that does not change a sealed version payload. It receives exact-path validation and affected tests but is not a Framework version release.
- `PATCH`: a bounded compatible correction that adds no public capability, authority action, schema migration, role, backend or consumer requirement.
- `MINOR`: a new Framework capability or public process/schema behavior with compatible project adoption.

Unknown impact, a new authority boundary or a migration requirement cannot be classified as PATCH. Classification changes before candidate freeze reopen scope and authorization.

## Direct-version candidate

Develop a new version directly in `framework/versions/<version>/`; no parallel draft tree is required. A directory is not consumable merely because it exists. Registration and upgrade require stable lifecycle fields plus a complete canonical `RELEASE_MANIFEST.json` with `sourceReview=APPROVED` and non-pending integration.

The version payload contains only version-owned runtime rules, schemas, compatibility/adoption facts, tests and explanatory material. It does not copy this release process. Version-specific release identity and evidence belong in `VERSION.json`, `RELEASE_MANIFEST.json`, `CHANGELOG.md` and the Maintenance task evidence.

## Candidate and testing

The payload is every file in the version except `RELEASE_MANIFEST.json`, ordered by ordinal relative path. Each row is `path|byteLength|UPPER_SHA256`; rows join with UTF-8 LF and no trailing LF; the payload identity is SHA256 over those rows.

During implementation run affected tests. At final candidate freeze run the complete current-version suite once. Always prove the immutable baseline payload identity. Re-run a baseline's executable suite only when shared root tools, upgrade compatibility, Tool Contract or that baseline's execution boundary is affected.

Freeze final current-facing README/ROADMAP wording before Source Review. Do not change free-form or executable bytes during deterministic sealing.

## Review, acceptance and sealing

1. Freeze the exact non-consumable candidate and release the writer.
2. One independent CRITICAL Source Review evaluates every changed normative/executable byte, exact payload, affected root projection, tests and immutable baseline boundary.
3. Same-scope repairs return to the same still-independent Reviewer for a focused rereview; broadened impact requires a full rereview.
4. Maintenance `OWNER_ACCEPT` separately accepts the exact approved candidate.
5. A bounded sealing writer changes only enumerated lifecycle fields and the excluded release manifest. Reviewed/generated root projections must already contain their final wording.
6. Deterministic checks recompute the final payload and verify the seal allowlist, manifest and staged diff. A second semantic post-seal Review is unnecessary when no unreviewed free-form or executable byte changed. Any such change reopens Source Review.
7. `GIT_STAGE` stages only the exact sealed allowlist. Before commit, a deterministic publication preflight must prove that the index pathset and every staged object identity equal the approved postimage, no unauthorized path is staged, release paths have no unstaged delta, the authorized parent is unchanged and all remote preconditions still match.
8. When every preflight fact is mechanically proven, `GIT_COMMIT` may proceed without a routine independent staged Git Review. Any path, byte, parent, repository-boundary or integration ambiguity stops the commit: use an independent staged Git Review when the approved postimage is unchanged but publication integrity cannot be established mechanically, or reopen Source Review when free-form/executable candidate bytes changed. After commit, verify the resulting commit, parent, committed pathset and protected-safe repository state before any remote action.
9. This Framework repository publishes `github/main` first and `origin/main` second. Before the first push, both remote refs must equal the authorized parent; after each push, read back that remote at the exact release commit. Any preflight, push or readback failure stops the sequence before the later remote and forbids implicit retry, force, tag or compensation without fresh recovery and authority.

One explicit user authorization may pre-authorize this exact ordered Git sequence, but it does not merge its action packages, evidence or failure boundaries.

Review approval, `OWNER_ACCEPT`, sealing, Git publication and consumer adoption are distinct outcomes. A stable release never selects a global default or changes a project pin.

## Incorporated corrections and platform evidence

Correction coverage metadata cannot prove incorporation by itself. Suppression requires the original reason and boundary to be implemented in applicable native requirements, covered by behavior tests and accepted in Source Review with exact mapping evidence.

Platform support remains evidence-bound. A release claims only the platforms declared by its sealed Tool Contract and supported by actual conformance evidence.

This process adds no release service, registry, queue, ledger, persistent receipt, second authority or automatic consumer operation.
