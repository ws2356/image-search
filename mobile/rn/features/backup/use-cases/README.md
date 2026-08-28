# Backup Use Cases

This folder holds the **application-layer actions** for the backup flow.

## Why this layer exists

Use-cases keep UI components thin and move business actions into reusable functions.

- UI (`screens/`, `hooks/`) says **what user wants to do**
- Use-case says **how that action runs in app logic**
- Transition helper (`state/backup-flow-transition-helper.ts`) applies flow-state mutations
- Infrastructure ports (`infrastructure/*`) do external I/O

This gives cleaner tests, easier refactors, and less duplicated flow logic.

## Current files

- `process-incoming-link.ts`: parse/accept incoming pairing link payload
- `run-preflight.ts`: execute preflight checks before transfer
- `start-transfer.ts`: start transfer flow and seed initial snapshot
- `stop-transfer.ts`: request transfer stop path
- `finish-transfer.ts`: complete transfer success path
- `return-home.ts`: reset flow back to home

## Design rules in this repo

1. One file = one user-intent action.
2. Keep network/storage/platform APIs behind injected ports.
3. Keep route/UI concerns out of use-cases.
4. Prefer explicit input/output types.
5. If a use-case needs fallback/stub behavior in early phases, keep it explicit (no silent success defaults).

## Typical call path

`Screen` -> `Hook controller` -> `Use-case` -> `Transition helper + Ports` -> `Store updates`
