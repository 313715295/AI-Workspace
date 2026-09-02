# Framework 1.15.1 versus 1.16.0

| Concern | 1.15.1 | 1.16.0 candidate |
|---|---|---|
| adoption facts | target-specific root-tool branches and release prose | one fixed `ADOPTION_PROFILE.json` consumed by generic root integration |
| direct sources | bounded 1.14.x bridge | profile-declared 1.14.1, 1.15.0 and 1.15.1 |
| normal selected pack | 12288-byte current-pin ceiling plus a bounded upgrade bridge | 32768-byte ordinary ceiling and 65536-byte general absolute ceiling |
| legacy schema1 exception | bridge-specific compatibility behavior | verified no-custom/clear/no-mismatch compatibility up to 98304 bytes with a visible marker |
| DISCOVER output | complete selected canonical blocks used as the boundary receipt | complete blocks once plus a compact reusable no-`fullText` receipt |
| temporary process input | caller-owned lifecycle | optional exact safe cleanup of non-reparse temp `aiw-*.json` on success or failure |
| active task finalization | ordinary source identity drift blocks FINALIZE | one narrow schema2 CONTROL task preimage-to-postimage transition; all other drift still blocks |
| capability bridge | target-specific Knowledge capability handling | exact ordinal-sorted enabled capability IDs passed unchanged; hints grant nothing |
| release rules in runtime selection | release fragment participates in the generated catalog | release governance remains normative but is outside the normal runtime fragment/catalog surface |
| stable payloads | immutable through 1.15.1 | unchanged; 1.16.0 is a new candidate directory |
| added machinery | one resolver/composer and existing root tools | no new service, registry, ledger, cache, poller or second authority |
