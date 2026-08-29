# Framework 1.12.0 release governance

Framework 1.12.0 is a MINOR release from immutable stable 1.11.0.

## Direct-version candidate

Development occurs directly in `framework/versions/1.12.0/`. The directory is not consumable merely because it exists. Root registration and upgrade require a complete canonical manifest with `sourceReview=APPROVED` and non-pending integration.

There is no required `framework/drafts/1.12.0` copy or projection.

## Candidate payload

The release payload is every file in this version except `RELEASE_MANIFEST.json`, ordered by ordinal relative path. Each row is `path|byteLength|UPPER_SHA256`; rows join with UTF-8 LF and no trailing LF; SHA256 of that payload is the canonical identity.

## Gates

1. exact inventory and strict text/JSON/PowerShell validation;
2. direct positive/negative contract tests;
3. stable 1.11.0 identity and regression checks;
4. actual PowerShell 7 conformance on Windows, Ubuntu/Linux and macOS using the same normalized fixture contract;
5. candidate freeze and writer release;
6. fresh independent CRITICAL source Review;
7. manifest seal and focused integration verification;
8. separate Git stage/commit and push decisions.

Review findings are repaired in the same 1.12.0 object under fresh write authority. Do not pre-plan a patch release for candidate defects.

A stable release does not select a global default and does not alter any project pin.

Cross-platform support is evidence-bound. A workflow definition or local Windows pass does not substitute for actual successful Ubuntu and macOS runs. Missing platform evidence blocks the stable seal.

## Incorporated correction acceptance

`CORRECTION_COVERAGE.json` is release metadata, not proof that a requirement was implemented. Before a correction ID may appear as incorporated for this release, its effective requirement must be present in the applicable normative modules selected by `LOAD_MANIFEST.json`, have direct behavioral tests, and be evaluated by independent Review against the original requirement reason and boundary. Similar wording or the coverage row alone is insufficient.

This gate adds no correction-to-module registry, runtime ledger or second correction state. Release evidence and tests carry the proof for the current candidate.
