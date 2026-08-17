# Framework release governance

## 1. Version classes

- `PATCH_HOTFIX`: compatible narrow correction; no new public topology.
- `MINOR`: compatible capability or project-control contract with migration.
- `MAJOR`: incompatible project/task/authority topology.

Framework 1.6.1 is a `PATCH_HOTFIX` candidate from immutable stable 1.6.0. It changes no public topology: the existing knowledge checker gains one optional exact selector and the existing root adoption path recognizes the new pin. The implementation candidate, independent Review, stable projection, live root replacement, CURRENT selection, every project pin and Git publication are separate objects and actions.

## 2. 1.6.1 release gates

1. exact candidate inventory, strict UTF-8/LF, JSON and PowerShell syntax;
2. stable 1.6.0 payload and live roots remain byte-identical;
3. explicit Entry ID positive/negative cases, including proof that unselected CURRENT drift still fails the whole query;
4. omitted Entry ID preserves 1.6.0 result behavior;
5. 1.6.1 registration and 1.6.0→1.6.1 preview/apply/repeat/recovery use the existing transaction and preserve controller/custom bytes;
6. existing 1.4.1/1.5.x→1.6.0 coverage remains green;
7. manifest, load costs and old-mechanism absence are re-frozen;
8. fresh independent CRITICAL Review of the frozen exact range.

Tests prove only their actual isolated/static boundaries. Candidate PASS is not formal release, CURRENT selection, Pocket adoption, a natural knowledge query or Git publication.

## 3. Publication order

Freeze candidate and manifest, obtain independent Review, project the approved exact range to an immutable stable version, then separately decide live-root replacement, CURRENT and project adoption. No project is upgraded automatically.

Stable versions are never edited in place. A later correction creates a new version.
