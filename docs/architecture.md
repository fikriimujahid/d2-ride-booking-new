
# Architecture (Phase 1)
# https://dreampuf.github.io/GraphvizOnline/
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

## DEV infrastructure diagram (Inframap)

**What is Inframap?**
Inframap is a CLI tool that converts Terraform inputs/state into a graph, producing DOT output that can be rendered into human-readable diagrams.

**What it visualizes**
It highlights infrastructure nodes and relationships (e.g., VPC, subnets, security groups, IAM roles, RDS), which is ideal for documentation and onboarding.

**Scope and intent**
- DEV environment only (from `infra/terraform/envs/dev`)
- Documentation/understanding only
- No changes are applied to infrastructure
- No AWS credentials are required

**Generated artifacts**
- [docs/diagrams/dev-infra.dot](docs/diagrams/dev-infra.dot)
- [docs/diagrams/dev-infra.svg](docs/diagrams/dev-infra.svg)
- [docs/diagrams/dev-infra.png](docs/diagrams/dev-infra.png)

**How to generate/update**
Run the script below from the repository root:

- [infra/scripts/generate-diagram.sh](infra/scripts/generate-diagram.sh)

The script will:
- run `terraform init` (safe, no apply)
- run `terraform graph` and pipe to Inframap (DEV-only)
- fall back to DEV `terraform.tfstate` if needed
- emit a DOT file plus SVG/PNG renders

**Diagram clarity settings**
The script uses Inframap flags to reduce noise and keep the diagram readable:
- `--clean`: remove disconnected nodes
- `--external-nodes=false`: hide external ingress/egress nodes
- `--raw`: include all resources from the DEV state (useful with modules)

**Validation checklist (comments)**
- Diagram shows VPC, subnets, RDS, EC2 roles, security groups
- Diagram generation is repeatable
- No infrastructure changes occur
- Diagram is suitable for README or presentation

## CI/CD philosophy

- CI triggers only on PRs to `dev` and only when relevant paths change.
- Security checks are part of CI from day 1:
	- ESLint
	- TypeScript strict mode
	- `npm audit`
	- Semgrep (SAST) using default rules (`p/default`)
- No cloud credentials and no deployment steps.

### CI (optional, document-only)

In the future, we can add a CI job to run the diagram script on PRs and upload the SVG/PNG as build artifacts. This helps reviewers quickly see infrastructure changes, improves architectural documentation, and reduces drift between code and diagrams without requiring any deployment.

