
# Cost strategy (DEV-first)

Phase 1 has no cloud provisioning, but cost discipline is designed in from day 1.

## Principles

- DEV is cost-first and fast feedback.
- PROD is reliability-first and secure-by-default.
- Treat infrastructure as code with explicit toggles.

## Feature toggles

- Disable non-critical, high-cost features by default in DEV (e.g., realtime dashboards, high-frequency telemetry).
- Prefer sampling and lower retention windows in DEV.

## Infra toggles (planned)

In Terraform modules, plan for toggles such as:

- ALB on/off (or swap to simpler ingress in DEV)
- NAT on/off (use private egress only when required)
- ASG on/off (single instance in DEV)

## Why DEV ≠ PROD

- DEV focuses on learning and iteration; over-provisioning hides performance and cost issues.
- PROD requires redundancy, security controls, and observability that are intentionally not “always on” in DEV.

