# Framework 1.7.0 versus 1.8.0

| Concern | 1.7.0 | 1.8.0 |
|---|---|---|
| new-project version | root selector could supply a default | exact version required |
| release development | draft projection flow | direct final-version candidate, sealed before consumption |
| consumer adoption | project-local | project-local; explicitly no registry or automatic upgrade |
| launch | recovery and start could require repeated round trip | valid signed package closes launch |
| task routing | mostly narrative | `REUSE / MUST_NEW / BLOCKED` boundary |
| action authorization | one observed action per call | action batch with per-action results |
| mutable-card manifest | absent | still absent |
| authorization ledger | absent | still absent |
| knowledge timestamps | PS5.1 behavior | PS5.1 and PS7 string-compatible |
| safety | one writer, protected paths, independent gates | preserved |
