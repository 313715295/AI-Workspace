# Framework 1.12.0 release governance

Framework 1.12.0 is a MINOR release from immutable stable 1.11.0.

## Direct-version candidate

Development occurs directly in `framework/versions/1.12.0/`. The directory is not consumable merely because it exists. Root registration and upgrade require a complete canonical manifest with `sourceReview=APPROVED` and non-pending integration.

There is no required `framework/drafts/1.12.0` copy or projection.

## Candidate payload

The release payload is every file in this version except `RELEASE_MANIFEST.json`, ordered by ordinal relative path. Each row is `path|byteLength|UPPER_SHA256`; rows join with UTF-8 LF and no trailing LF; SHA256 of that payload is the canonical identity. Final `VERSION.json` lifecycle fields are part of this payload and therefore are projected before the final exact source Review. Until the excluded manifest is sealed as approved, registration and upgrade still reject the release.

## Gates

1. exact inventory and strict text/JSON/PowerShell validation;
2. direct positive/negative contract tests;
3. stable 1.11.0 identity and regression checks;
4. actual PowerShell 7 conformance on every platform declared by `TOOLCHAIN.json`; 1.12.0 declares Windows only;
5. project final `VERSION.json` fields, freeze the exact payload and release the writer;
6. fresh independent CRITICAL source Review of that final payload;
7. change only excluded `RELEASE_MANIFEST.json` plus the reviewed root integration projection, then verify the payload is byte-identical;
8. separate Git stage/commit and push decisions.

Review findings are repaired in the same 1.12.0 object under fresh write authority. Do not pre-plan a patch release for candidate defects.

A stable release does not select a global default and does not alter any project pin.

Platform support is evidence-bound. 1.12.0 claims Windows only, so its Windows run is the release gate. Linux/macOS are not inferred from PowerShell portability; admitting either later requires an updated released toolchain declaration and its own conformance evidence.

## Incorporated correction acceptance

`CORRECTION_COVERAGE.json` is release metadata, not proof that a requirement was implemented. Before a correction ID may appear as incorporated for this release, its effective requirement must be present in the applicable normative modules selected by `LOAD_MANIFEST.json`, have direct behavioral tests, and be evaluated by independent Review against the original requirement reason and boundary. Similar wording or the coverage row alone is insufficient.

This gate adds no correction-to-module registry, runtime ledger or second correction state. Release evidence and tests carry the proof for the current candidate.
