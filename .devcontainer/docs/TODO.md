# DevContainer TODO (checklist, traceable)

- [ ] REQ-PERF-006 — Registry build-cache workflow  — Owner: DevOps | Effort: 2d
  - [ ] CI publishes `cache-*` tags
  - [ ] Local `use-registry-cache.sh` demonstrates >70% cache hit
  - Files: `.github/workflows/devcontainer-prebuild.yml`, `.devcontainer/Dockerfile.optimized`, `.devcontainer/scripts/use-registry-cache.sh`

- [ ] REQ-PERF-007 — Persistent volumes & volume manager — Owner: DevOps | Effort: 1d
  - [ ] `manage-volumes.sh create` creates required volumes
  - [ ] `verify-volumes.sh` passes all checks
  - Files: `.devcontainer/docker-compose.persistent.yml`, `.devcontainer/scripts/manage-volumes.sh`

- [ ] REQ-ARCH-001 — Modularize scripts & shellcheck — Owner: Dev | Effort: 3d
  - [ ] Library functions pass shellcheck
  - [ ] `verify-env.sh` returns expected exit codes
  - Files: `.devcontainer/scripts/lib/*`, `.devcontainer/scripts/{init-env,setup-env,verify-env}.sh`

- [ ] REQ-ARCH-002 / REQ-CICD-001 — CI prebuild + multi-arch images — Owner: DevOps | Effort: 3d
  - [ ] Buildx produces multi-arch images and manifest
  - [ ] CI artifacts (digests) uploaded as expected
  - Files: `.github/workflows/devcontainer-prebuild.yml`, `.github/workflows/devcontainer-registry-cache.yml`

- [ ] REQ-SEC-001 — Secure .env & secret handling — Owner: Dev | Effort: 1d
  - [ ] `.devcontainer/.env` created with 0600 in setup flow
  - [ ] `verify-env.sh` validates presence but does not echo secrets
  - Files: `.devcontainer/.env.example`, `.devcontainer/scripts/setup-env.sh`, `.devcontainer/scripts/verify-env.sh`

- [ ] REQ-TEST-001 — Verification tests & CI gating — Owner: QA/Dev | Effort: 2d
  - [ ] CI job fails on critical regressions (cache publish, env verify, volumes)
  - [ ] Fast local `./devcontainer/tests/*` smoke checks exist
  - Files: `.devcontainer/tests/*`, `.github/workflows/devcontainer-ci.yml`

- [ ] REQ-MON-001 / REQ-MON-002 — Metrics & alerting for prebuilds — Owner: DevOps | Effort: 2d
  - [ ] `metrics.jsonl` produced for prebuilds
  - [ ] Alerts trigger on repeated cache-miss regressions
  - Files: `.devcontainer/scripts/lib/core.sh`, `.github/workflows/devcontainer-prebuild.yml`

- [ ] REQ-COMP-001 — SBOM generation in CI — Owner: Sec/DevOps | Effort: 1d
  - [ ] SBOM artifact generated and attached to prebuild run
  - Files: `eng/common/core-templates/steps/generate-sbom.yml`, `.github/workflows/*`

- [ ] Docs: Revise `.devcontainer/docs/DEVELOPMENT_DEBT.md` — Owner: Doc/Dev | Effort: 1d
  - [ ] Remove legacy footer headers and add consistent front-matter
  - [ ] Ensure consistency with TECHNICAL_DEBT_REPORT and ARCHITECTURE_REQUIREMENTS
  - Files: `.devcontainer/docs/DEVELOPMENT_DEBT.md`

Notes:
- Mark the top-level checklist item done when all nested acceptance checkboxes are complete and a PR is merged (include PR link next to the item).
