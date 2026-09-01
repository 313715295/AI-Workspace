# Framework 1.15.1 migration matrix

| Source | Target | Required behavior |
|---|---|---|
| new project | explicit stable 1.15.1 | require PowerShell 7 and Controller ID; preview deterministic same-volume preparation plus fixed active/recovery locators and the exact 12-object write set; fully render, validate and bind the transaction before the first repository write; create schema4 config, schema2 corrections and an empty process-policy carrier; project only the managed `AGENTS.md` block and never install a repo-local Skill |
| healthy repo-local schema4 1.14.0 or 1.14.1 | 1.15.1 | require one current active Framework-adoption task with an explicitly bound actor plus one closed schema3 `ACTOR_BOUND_PROJECT_UPGRADE` package; if and only if the sealed current-pin process resolver fails solely with `SELECTED_RULE_PACK_BUDGET_EXCEEDED`, independently compose and retain the complete selected rule bodies under the 1.15.1 absolute ceiling before planning the ordinary actor-bound transition; preserve project facts, Controller, process-policy and corrections; project the target Bootstrap/pin/AGENTS block, remove only the exact sealed 1.14 repo-local Skill, write every non-task object before the task, write the task last and perform no later write |
| healthy repo-local schema4 1.15.0 | 1.15.1 | no direct adoption edge in this release; remain on 1.15.0 and adopt a later stable release whose migration matrix explicitly lists 1.15.0 as a supported source |
| healthy repo-local schema4 1.15.1 | 1.15.1 | validate backend, policy locator/object, Bootstrap, Controller, corrections and managed AGENTS projection through the pinned release, with no repo-local router Skill requirement; return already upgraded |
| 1.14 project with modified/missing managed AGENTS block or modified/extra/missing repo-local Skill bytes | 1.15.1 | stop before preparation with the exact conflict; do not normalize, delete or replace project-owned/unknown bytes |
| 1.14 project without a current actor-bound active task | 1.15.1 | stop with `ACTOR_BOUND_PROJECT_UPGRADE_ROUTE_REQUIRED`; no actor inference and no bulk task rewrite |
| schema3 or schema4 version earlier than 1.14.0 | 1.15.1 | blocked from the direct route; first adopt a supported stable intermediate version |
| schema3 project with free-text corrections | 1.15.1 | not a direct source; after a lawful intermediate migration, derive project-scoped aliases and canonical source identities, suppress only exact sealed mappings and retain unmatched records |
| project with normative `PROJECT-CUSTOM` | 1.15.1 | preserve it as current project authority until a separately reviewed atomic migration establishes one structured process-policy carrier; do not claim compact progressive selection for legacy free text |
| unavailable backend/runtime or unsupported platform | 1.15.1 | fail closed before project write; no install, download or implicit fallback |
| downgrade from 1.15.1 | older release | no automatic direct route; require a separately reviewed reverse migration that restores any release-specific project artifacts and avoids dual authority |

Adoption is project-owned. It never changes another project pin or installs the host-global Skill. The canonical Skill is published at `framework/versions/1.15.1/host/skills/ai-workspace-router/SKILL.md` with a byte-identical root projection for host installation, but host installation remains a separate host action.

## Actor-bound upgrade contract

The read-only plan is produced before any preparation write and reports:

- the sealed target release canonical plus manifest identity;
- every exact path and preimage;
- the final identity (or `ABSENT`) of every live object;
- deterministic preparation and formal recovery paths under `.ai-workspace`;
- the task as the final live object.

A valid schema3 package has exactly `bundle=ACTOR_BOUND_PROJECT_UPGRADE`, `profile=CRITICAL`, `issuerRole=PROJECT_CONTROLLER`, `actions=[CONTROL_WRITE]`, required Controller/task/project bindings, the complete exact path/preimage set and a `postObjectIdentities` entry for every live object. Paths without postimages are preparation/recovery material only and must have preimage `NEW`. `POST_OBJECT_DRIFT` is an invalidator. Schema1 and schema2 packages retain their existing contracts.

For the 1.14.x → 1.15.1 compatibility bridge, the caller also supplies one strict schema2 current-process input plus its whole-object identity. The input is read-only, actor/task/owner/Controller/project bound, names the current pinned Framework, carries the exact ordinary adoption exclusions and requests `NONE / PLAN`; it cannot authorize or describe source, test, Review, Git, external or product mutation. The upgrade tool invokes only the current pin's sealed `PROCESS_REQUIREMENTS_RESOLVE` entrypoint. Admission requires exit code 2 and the single exact reason `SELECTED_RULE_PACK_BUDGET_EXCEEDED`; every other PASS, failure, extra output or malformed result rejects the bridge. The tool then invokes that same pin's sealed composer once, requires a successful complete composition, retains every selected requirement's complete Markdown block and proves the selected pack is above the current ordinary ceiling but no larger than the 1.15.1 absolute ceiling. This evidence is a compatibility input only: it grants no action and does not replace the schema3 package, protected paths, task-last transaction, recovery, Review, `OWNER_ACCEPT`, Git or external gates.

On apply, the tool rechecks the package before the first write, prepares exact old/new/state material, validates it, atomically promotes it to the formal recovery directory, validates it again, then advances live non-task objects. The current task is validated and copied last. A successful task write is terminal for the transaction: no cleanup, status rewrite or other live/recovery write follows it.

A formal recovery directory is forward-only. Resume requires the same target release, package identity, actor/task/owner, Controller ID/epoch, exact state tree and final postimages. Every live object must equal either its original preimage or declared final identity; unknown/intermediate bytes fail closed. Preparation or recovery material is retained as evidence and is not silently cleaned.

## Progressive-loading migration effect

Existing 1.14 project corrections and structured process-policy records remain project authority. Framework-native rules use schema2 fragments and exact Markdown blocks only after the project adopts 1.15. Legacy free-text carriers remain complete-read compatibility inputs and must be reported as progressive-selection unproven. `LOAD_PLAN_RESOLVE` remains available for non-rule support and bounded affected-module fallback, not as a catalog exclusion step.
