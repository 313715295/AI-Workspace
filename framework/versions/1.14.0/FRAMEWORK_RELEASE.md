# Framework 1.14.0 release governance

Framework 1.14.0 is a MINOR release from immutable stable 1.13.0.

## Direct-version candidate

Development occurs directly in `framework/versions/1.14.0/`. The directory is not consumable merely because it exists. Root registration and upgrade require a complete canonical manifest with `sourceReview=APPROVED` and non-pending integration.

There is no required `framework/drafts/1.14.0` copy or projection.

## Candidate payload

The release payload is every file in this version except `RELEASE_MANIFEST.json`, ordered by ordinal relative path. Each row is `path|byteLength|UPPER_SHA256`; rows join with UTF-8 LF and no trailing LF; SHA256 of that payload is the canonical identity. Full source Review evaluates the exact non-consumable candidate. After Review approval and Maintenance OWNER_ACCEPT, the only permitted payload projection is the enumerated lifecycle seal: `VERSION.json` lifecycle/consumable/projectPinEligible and `LOAD_MANIFEST.json` lifecycle. A focused independent post-seal Review recomputes the final payload, confirms this exact delta and evaluates the excluded manifest plus root integration. Until that review is approved and `RELEASE_MANIFEST.json` is sealed, registration and upgrade reject the release.

## Gates

1. exact inventory and strict text/JSON/PowerShell validation;
2. direct positive/negative contract tests;
3. stable 1.13.0 identity and regression checks, including its Windows PowerShell 7 tool contract;
4. actual PowerShell 7 conformance on every platform declared by `TOOLCHAIN.json`; 1.14.0 declares Windows only;
5. freeze the exact non-consumable candidate payload and release the writer;
6. fresh independent CRITICAL source Review of that exact candidate;
7. Maintenance OWNER_ACCEPT of the exact approved candidate, without treating Review as owner acceptance or adding capability;
8. project only the enumerated lifecycle fields, the excluded `RELEASE_MANIFEST.json` and root integration; change no normative or executable payload byte;
9. focused independent post-seal Review verifies the exact allowed delta, recomputes the final stable payload and approves the final manifest/root projection;
10. separate Git stage/commit and push decisions.

Review findings are repaired in the same 1.14.0 object under fresh write authority. Do not pre-plan a patch release for candidate defects.

`PROCESS_REQUIREMENTS_EVALUATION.md` defines optional post-release project observation. It begins only after a project explicitly adopts the stable version, uses normal project tasks and never blocks this release, creates synthetic tasks, or becomes Framework-owned consumer evidence.

A stable release does not select a global default and does not alter any project pin.

Platform support is evidence-bound. 1.14.0 claims Windows only, so its Windows run is the release gate. Linux/macOS are not inferred from PowerShell portability; admitting either later requires an updated released toolchain declaration and its own conformance evidence.

## Incorporated correction acceptance

`CORRECTION_COVERAGE.json` is release metadata, not proof that a requirement was implemented. Before a correction may be suppressed in this release, its effective requirement must be present in the applicable native catalog/module, have direct behavioral tests, pass independent Review against the original reason and boundary, and carry an exact sealed alias/native/catalog/source-record mapping. Similar wording, a historical correction ID or a coverage row alone is insufficient.

This gate adds no correction-to-module registry, runtime ledger or second correction state. Release evidence and tests carry the proof for the current candidate.
