# Project lessons

Carry-forward memory: the why-it's-like-this and what-not-to-touch that git
history and code comments cannot hold. Maintained by /lesson. Read before
changing existing behaviour. Do not duplicate what code, docs, or git already
record - link to them.

## Reusable gotchas
<!-- generalisable traps and lessons; each links its evidence -->

## Decisions & deliberate behaviours
<!-- design decisions and intentional behaviours; behaviours name a guarding test, decisions give the trade-off -->

- **Preserve both Ignition entry paths.** The root-first flow must finish independently while leaving a canonical `ajt` checkout for later selective runs; this was chosen over a mandatory two-stage handoff because a new system may have no usable non-root login. Guarded by the `ubuntu-workflow-root` and `ubuntu-workflow-later` profiles in `tests/docker-integration.sh`; the flow is described in `README.md`.
- **Keep production sudo password-protected.** Chose a password prompt over unrestricted `NOPASSWD` access because coding agents run as the administrative user and should not gain silent root access; disposable test containers may use a test-only exception. Guarded by the `ubuntu-workflow-root` profile in `tests/docker-integration.sh`; see `README.md`.
- **Resume only a matching root-first checkout.** A retry reuses the destination only when its target ownership, branch, commit, and SSH origin match the bootstrap source; this preserves partial-failure recovery without treating an unrelated directory as Ignition state. Guarded by the `ubuntu-workflow-root` profile in `tests/docker-integration.sh`.
