# Framework 1.11.0 change log

Baseline: immutable Framework 1.10.0.

Release class: `MINOR`.

## Added

- one authoritative task-card `Work route: role + phase` for new schema 1.11.0 cards;
- task-bound load-plan resolution with role/profile/phase drift rejection;
- explicit `LEGACY_LOAD_CONTEXT` fallback for older cards without bulk migration;
- a boundary refresh contract for initial recovery, work-route transitions, compaction, pause/resume, handoff and uncertain context;
- release acceptance requiring incorporated corrections to exist in applicable normative modules, behavior tests and requirement-level independent Review.

## Changed

- Bootstrap passes the assigned task to the existing loader instead of treating caller-inferred role/profile/phase as equal authority;
- unchanged continuous work and authorization refresh do not reload modules;
- registration and upgrade explicitly support 1.11.0 while preserving project-owned pins, Controller identity, custom regions and correction bytes;
- new tasks use schema 1.11.0; legacy cards migrate only at a natural authorized task update.

## Preserved

- immutable Framework 1.10.0 and older releases;
- owner-first direct routing, independent Review, one-writer and separate Git/external gates;
- project-owned correction records and payload-sealed cumulative coverage;
- exact project-selected versions with no Framework-global CURRENT/default.

## Not added

No second refresh resolver, per-tool reload, host hook, attention monitor, Skill/plugin/tool governance, token-budget subsystem, Knowledge expansion, accepted-state projection, correction-to-module registry, absorption ledger, actor/Reviewer pool, ACK/heartbeat/polling, consumer registry or automatic project upgrade.
