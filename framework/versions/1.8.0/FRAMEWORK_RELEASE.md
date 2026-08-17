# Framework 1.8.0 release governance

Framework 1.8.0 is a MINOR release from immutable stable 1.7.0.

## Direct-version candidate

Development occurs directly in `framework/versions/1.8.0/`. The directory is not consumable merely because it exists. Root registration and upgrade require a complete canonical manifest with `sourceReview=APPROVED` and non-pending integration.

There is no required `framework/drafts/1.8.0` copy or projection.

## Candidate payload

The release payload is every file in this version except `RELEASE_MANIFEST.json`, ordered by ordinal relative path. Each row is `path|byteLength|UPPER_SHA256`; rows join with UTF-8 LF and no trailing LF; SHA256 of that payload is the canonical identity.

## Gates

1. exact inventory and strict text/JSON/PowerShell validation;
2. direct positive/negative contract tests;
3. stable 1.7.0 identity and regression checks;
4. candidate freeze and writer release;
5. fresh independent CRITICAL source Review;
6. manifest seal and focused integration verification;
7. separate Git stage/commit and push decisions.

Review findings are repaired in the same 1.8.0 object under fresh write authority. Do not pre-plan a patch release for candidate defects.

A stable release does not select a global default and does not alter any project pin.
