
# Architecture (Phase 1)

## Why a monorepo

This repo groups related delivery units (API + 3 web apps + infra) into a single source-controlled system because:

- Shared standards (TypeScript strictness, lint rules, security scanning) are easiest to enforce centrally.
- Cross-cutting changes (API contract + UI updates) can be reviewed and tested together.
- CI can be **path-filtered** to stay fast while still being comprehensive.

## Clean application boundaries

- Each app owns its dependencies, build, and lint/typecheck configuration under `apps/<name>`.
- Infra is isolated under `infra/terraform`.
- Docs live under `docs/` and are treated as a first-class deliverable.

## DEV vs PROD separation (conceptual)

Phase 1 intentionally has **no deployment**. However, we still separate intent:

- `infra/terraform/envs/dev`: cost-first, minimal toggles on by default
- `infra/terraform/envs/prod`: production-ready defaults (secure + scalable), not applied in Phase 1

This allows review of production posture without provisioning anything.

## CI/CD philosophy

- CI triggers only on PRs to `dev` and only when relevant paths change.
- Security checks are part of CI from day 1:
	- ESLint
	- TypeScript strict mode
	- `npm audit`
	- Semgrep (SAST) using default rules (`p/default`)
- No cloud credentials and no deployment steps.

