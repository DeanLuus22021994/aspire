---
title: "DevContainer Architecture & Sprint 2 Requirements"
version: "3.0.0"
last_updated: "2025-09-30"
status: "Implementation Ready with Full Traceability"
---

## Document purpose
This document specifies architecture and implementation requirements for the Aspire devcontainer workstream (Sprint 2 focus). It is implementation-ready and provides traceability to technical debt items, CI workflows, scripts, and verification tests.

Note: Refer to `.devcontainer/docs/agile/TECHNICAL_DEBT_REPORT.md` for background and prioritization rationale.

## Scope
- CI/CD prebuilds, registry caching, and Buildx multi-arch builds
- Persistent caches and volume management for developer productivity
- Modular script architecture for init/setup/verify workflows
- Security and secret management for environment variables (non-production secret recommendations)
- Verification tests and acceptance criteria for each requirement

Non-goals: full external secret vault integration (e.g., production Key Vault wiring) and enterprise policy enforcement beyond recommended patterns.

## Constraints & Assumptions
- Developers use WSL2 on Windows or Linux hosts (behaviour differences explained in implementation notes).
- The devcontainer uses a single Dockerfile-based build (prefer BuildKit / Buildx). Avoid Docker Compose for container image build in primary flow unless explicitly required.
- Required environment variables: GH_PAT, GITHUB_OWNER, GITHUB_RUNNER_TOKEN, DOCKER_ACCESS_TOKEN, DOCKER_USERNAME. These must never be committed to repo.
- Registry for cache images: GitHub Container Registry (GHCR) is the recommended default; workflows must allow substitution for other registries.

## High-level goals
- Reduce local container cold-start times by 70% using registry and local cache strategies.
- Provide reproducible, multi-arch devcontainer images for AMD64 and ARM64.
- Implement modular, testable bash libraries for script reuse and observability.
- Ensure secure handling of developer secrets and permissions for env files.

## Traceability tag format
All requirements use the format `[TAG-{CATEGORY}-{NNN}]` where CATEGORY ∈ {ARCH, PERF, CICD, TEST, SEC}.

---

## Requirements

### [TAG-ARCH-001] REQ-ARCH-001: Modular Scripts Architecture
Priority: P1 | Sprint: 1 | Effort: 3d | Owner: Dev
Technical Debt ID: TD-011

Requirement:
- Break monolithic scripts into a small library under `.devcontainer/scripts/lib/` (core logging, file_ops, env management, validation, github_api, docker_api).
- Expose well-documented, single-purpose entry scripts under `.devcontainer/scripts/` (init-env.sh, setup-env.sh, verify-env.sh, quick-start.sh, manage-volumes.sh).
- Provide robust error handling (trap), structured logging, and metrics collection hooks.

Acceptance criteria / tests:
- Unit-like sharness or shellcheckable functions exist and are covered by `scripts/tests/` shell scripts.
- `bash .devcontainer/scripts/verify-env.sh` exits 0 when valid env is present and non-zero otherwise.

Implementation notes:
- See `.devcontainer/scripts/lib/core.sh` for logging and error trap.
- Keep scripts idempotent and safe for repeated execution.

---

### [TAG-PERF-006] REQ-PERF-006: Registry-based Build Cache
Priority: P1 | Sprint: 2 | Effort: 2d | Owner: DevOps
Technical Debt ID: TD-006

Requirement:
- CI workflow must build and publish cache-enabled images for target platforms (amd64, arm64) to registry with stable `cache-*` tags.
- Use `docker/build-push-action@v5` (Buildx) with `cache-from` and `cache-to` semantics and `BUILDKIT_INLINE_CACHE=1` as a build-arg where appropriate.
- Workflow must support scheduled warm-up runs and manual dispatch.

Acceptance criteria / tests:
- `workflow: devcontainer-registry-cache.yml` publishes `cache-amd64` and `cache-arm64` tags.
- Local developer command `.devcontainer/scripts/use-registry-cache.sh` can pull cache images and produce a significant cache hit rate (>70%) measured by `docker buildx du` and build timings.
- Verify with `.devcontainer/tests/verify-registry-cache.sh`.

Notes:
- Default registry: `ghcr.io`. Allow environment overrides via workflow inputs or repository secrets.
- Keep registry scopes and PATs scoped to minimal privileges (package write for pushing images).

---

### [TAG-PERF-007] REQ-PERF-007: Persistent Volume Strategy
Priority: P1 | Sprint: 1 | Effort: 1d | Owner: DevOps
Technical Debt ID: TD-007

Requirement:
- Define named Docker volumes or host-bind paths for: NuGet cache (~1.5GB), npm cache (~500MB), pip cache, .NET tools, obj/bin caches, VS Code server and extensions.
- Provide a `docker-compose` volume-only file for local volume lifecycle (`.devcontainer/docker-compose.volumes.yml`) and a `manage-volumes.sh` script to initialize/backup/restore.
- Use tmpfs drivers for ephemeral build-stage caches where appropriate, with documented sizing.

Acceptance criteria / tests:
- Running `bash .devcontainer/scripts/manage-volumes.sh init` creates host directories and Docker volumes.
- `scripts/tests/verify-volumes.sh` demonstrates persistence across rebuilds and reports cache sizes.

Security/Isolation:
- Do not mount host SSH keys or Git config writeable into container by default. Where bind mounts are required, mark them read-only.

---

### [TAG-CICD-001] REQ-CICD-001: Build Performance and Multi-Arch Support
Priority: P1 | Sprint: 2 | Effort: 3d | Owner: DevOps

Requirement:
- CI must use Buildx with QEMU to produce multi-arch images; images pushed for `linux/amd64` and `linux/arm64`.
- CI must configure a Buildx builder with appropriate worker and GC settings and capture build metrics (time, cache hits).
- Where possible, export intermediate caches to registry and to local cache artifacts to reduce rebuild time.

Acceptance criteria / tests:
- `devcontainer-prebuild.yml` executes Buildx multi-arch builds and publishes images with tags for both architectures.
- `devcontainer-prebuild.yml` emits build duration and cache metrics to job logs and optionally a summary JSON artifact.

---

### [TAG-SEC-001] REQ-SEC-001: Secure Handling of Secrets & Environment
Priority: P1 | Sprint: 1 | Effort: 1d | Owner: Dev

Requirement:
- Required secret variables (GH_PAT, GITHUB_RUNNER_TOKEN, DOCKER_ACCESS_TOKEN, DOCKER_USERNAME) must never be committed.
- Provide `.devcontainer/.env.example` and a setup script to create `.devcontainer/.env` with 0600 permissions.
- CI workflows must use repository secrets and avoid echoing secrets in logs. Use `docker/login-action` with `secrets.GITHUB_TOKEN` or scoped PATs.
- Recommend secret vaults (GitHub Secrets, Azure Key Vault, 1Password) for persistent team secrets; provide integration guides as future work.

Acceptance criteria / tests:
- `bash .devcontainer/scripts/setup-env.sh --non-interactive` creates `.devcontainer/.env` with 0600 and correct keys set from provided input file.
- `bash .devcontainer/scripts/verify-env.sh` validates presence but never prints secret values to logs.

---

### [TAG-TEST-001] REQ-TEST-001: End-to-end verification & CI gating
Priority: P2 | Sprint: 2 | Effort: 2d | Owner: QA/Dev

Requirement:
- Provide lightweight verification tests runnable in CI: volume checks, registry cache checks, env validations, basic container smoke test (container starts, core tools available).
- Mark long-running or flaky tests with `quarantined=true` and `outerloop=true` traits in test projects.

Acceptance criteria / tests:
- CI job `devcontainer-ci.yml` runs verification steps and fails when critical checks (cache publish, env verify) fail.
- Tests exist in `.devcontainer/tests/*` and are runnable locally.

---

## Implementation references (files & entry points)
- devcontainer config: `.devcontainer/devcontainer.json` (build args, runArgs, remoteEnv)
- Dockerfiles: `.devcontainer/Dockerfile`, `.devcontainer/Dockerfile.optimized` (multi-stage optimization)
- Scripts: `.devcontainer/scripts/` and `.devcontainer/scripts/lib/`
- Volume compose: `.devcontainer/docker-compose.volumes.yml`
- CI workflows: `.github/workflows/devcontainer-registry-cache.yml`, `.github/workflows/devcontainer-prebuild.yml`, `.github/workflows/devcontainer-ci.yml`
- Tests: `.devcontainer/tests/verify-registry-cache.sh`, `.devcontainer/tests/verify-volumes.sh`, other verification scripts

## Metrics & Observability
- Track metrics: build time (s), cache hit rate (%), image size (MB), number of layers cached, cold-start time (s).
- Provide `metrics.jsonl` output from scripts for CI ingestion and future dashboards.

## Risks & mitigations
- Risk: Secrets leakage in logs — Mitigation: redact secrets, avoid printing env values, use actions that mask secrets.
- Risk: CI cache poisoning or stale caches — Mitigation: use cache keys with hash of `.devcontainer` files and periodic scheduled rebuilds.
- Risk: Host differences (WSL2 vs Linux) — Mitigation: document platform-specific notes and provide scripts that detect platform and alter behavior.

## Owners & estimates
- Dev (scripts, modularization): 3 days
- DevOps (CI prebuild and Buildx configuration): 3 days
- DevOps (volume configuration and manage-volumes scripts): 1 day
- QA (tests and CI gating): 2 days

## Next steps / implementation plan
1. Finalize and lint `core.sh` and other lib scripts; add shellcheck CI job. [TAG-ARCH-001]
2. Merge `devcontainer-registry-cache.yml` workflow and validate with a dry-run using `devcontainer/Dockerfile.optimized`. [TAG-PERF-006]
3. Implement volume init script and run `verify-volumes.sh` in CI (container-in-container runner or dedicated runner). [TAG-PERF-007]
4. Add `devcontainer-ci.yml` with verification stages and gating for PRs modifying `.devcontainer/**` files. [TAG-TEST-001]

---

Document history
- 3.0.0 — 2025-09-30 — Implementation-ready; cleaned and stabilized after prior partial/duplicated content.