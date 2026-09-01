# Framework release governance

<!-- AIW-REQUIREMENT:PR_RELEASE_CLASSIFICATION:BEGIN -->
Framework 1.15.1 is a PATCH whose immutable implementation and release-lineage baseline is stable 1.15.0. That baseline does not create a 1.15.0 → 1.15.1 adoption edge: this release supports only new-project registration and direct adoption from healthy repo-local schema4 1.14.0/1.14.1 projects, exactly as listed in `MIGRATION_MATRIX.md`, and uses the proportional release flow below.

## Release classification

- `ROOT_MAINTENANCE`: bounded repository-level documentation, license, checkout policy or integration metadata that does not change a sealed version payload. It receives exact-path validation and affected tests but is not a Framework version release.
- `PATCH`: a bounded compatible correction that adds no public capability, authority action, schema migration, role, backend or consumer requirement.
- `MINOR`: a new Framework capability or public process/schema behavior with compatible project adoption.

Unknown impact, a new authority boundary or a migration requirement cannot be classified as PATCH. Classification changes before candidate freeze reopen scope and authorization.
<!-- AIW-REQUIREMENT:PR_RELEASE_CLASSIFICATION:END -->

<!-- AIW-REQUIREMENT:PR_DIRECT_VERSION_CANDIDATE:BEGIN -->
## Direct-version candidate

Development occurs directly in `framework/versions/<version>/`; no parallel draft tree is required. A directory is not consumable merely because it exists. Registration and upgrade require stable lifecycle fields plus a complete canonical `RELEASE_MANIFEST.json` with `sourceReview=APPROVED` and non-pending integration.
<!-- AIW-REQUIREMENT:PR_DIRECT_VERSION_CANDIDATE:END -->

<!-- AIW-REQUIREMENT:PR_RELEASE_CANDIDATE_TESTING:BEGIN -->
## Candidate and testing

The payload is every file in the version except `RELEASE_MANIFEST.json`, ordered by ordinal relative path. Each row is `path|byteLength|UPPER_SHA256`; rows join with UTF-8 LF and no trailing LF; the payload identity is SHA256 over those rows.

During implementation run affected tests. At the final candidate freeze run the complete current-version suite once. Always prove the immutable baseline payload identity. Re-run the baseline's executable suite only when shared root tools, upgrade compatibility, Tool Contract or that baseline's execution boundary is affected.
<!-- AIW-REQUIREMENT:PR_RELEASE_CANDIDATE_TESTING:END -->

<!-- AIW-REQUIREMENT:PR_PROPORTIONAL_RELEASE_SEQUENCE:BEGIN -->
## Review and sealing

1. Freeze the exact non-consumable candidate and release the writer.
2. One independent CRITICAL Source Review evaluates every changed normative/executable byte, exact payload, affected root projection, tests and immutable baseline boundary.
3. Same-scope repairs return to the same still-independent Reviewer for a focused rereview; broadened impact requires a full rereview.
4. Maintenance OWNER_ACCEPT separately accepts the exact approved candidate.
5. A bounded sealing writer changes only the enumerated lifecycle fields, the excluded manifest and exact reviewed/generated root projection.
6. Deterministic checks recompute the final payload, verify the seal allowlist, manifest and staged diff. A second independent semantic post-seal Review is not required when those checks prove no unreviewed free-form or executable change. Any such change reopens Source Review.
7. Git stage, commit and push remain categorical gates. One explicit user authorization may cover their exact ordered sequence; failure stops later actions.

Review approval, OWNER_ACCEPT, sealing, Git publication and consumer adoption remain distinct outcomes. A stable release never selects a global default or changes a project pin.
<!-- AIW-REQUIREMENT:PR_PROPORTIONAL_RELEASE_SEQUENCE:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTION_INCORPORATION_EVIDENCE:BEGIN -->
## Incorporated corrections and evidence

Correction coverage metadata cannot prove incorporation by itself. Suppression still requires the original reason and boundary to be implemented in applicable native requirements, covered by behavior tests and accepted in Source Review with exact mapping evidence.

Platform support remains evidence-bound. 1.15.1 claims Windows PowerShell 7 only. Linux/macOS require a later released toolchain declaration and actual conformance evidence.

This flow adds no release service, registry, queue, ledger, persistent receipt, second authority or automatic consumer operation.
<!-- AIW-REQUIREMENT:PR_CORRECTION_INCORPORATION_EVIDENCE:END -->
