# PROD Terraform Environment

This folder defines the **production** environment.

## Non-negotiable principles

- **DEV and PROD are fully isolated**
  - No shared VPC/subnets/security groups
  - No shared databases
  - No shared Cognito user pools
  - No shared IAM roles/instance profiles
  - No shared S3 buckets

Why: Sharing resources between environments collapses blast radius and makes auditing ambiguous (it becomes unclear which environment is impacted by a change).

## High-level architecture

- **Multi-AZ VPC**
  - Public subnets: ALB + NAT Gateways
  - Private app subnets: Auto Scaling Groups (backend-api, web-driver)
  - Private DB subnets: RDS (no public access)
- **Internet-facing ALB** with host-based routing
  - `api.d2.<domain>`
  - `driver.d2.<domain>`
- **RDS MySQL**
  - Multi-AZ enabled
  - IAM DB authentication enabled
  - Backups enabled (retention configured)

## Deployment safety (reversible)

- Instances are behind an ALB and registered via ASGs.
- Deployments happen via S3 + SSM (no SSH) and are designed to be **repeatable**.
- Rollbacks are done by redeploying a previous immutable artifact (previous `RELEASE_ID`).

## GitHub Actions (Prod environment setup)

The PROD deployment workflows are:

- `.github/workflows/backend-api-deploy-prod.yml`
- `.github/workflows/web-driver-deploy-prod.yml`

They expect a GitHub Actions **Environment** named `prod` with **required reviewers** enabled.

Required `prod` environment variables:

- `AWS_REGION`
- `S3_BUCKET_ARTIFACT` (the PROD artifacts bucket)
- `PUBLIC_API_BASE_URL` (for web-driver build, e.g. `https://api.d2.<domain>`)

Required `prod` environment secrets:

- `AWS_ROLE_ARN` (OIDC role to assume for deployments)
- `COGNITO_USER_POOL_ID` (PROD pool)
- `COGNITO_CLIENT_ID` (PROD app client)

Recommended: create and use the dedicated PROD deploy role

- Set `enable_github_actions_deploy_role=true` in `terraform.tfvars` and provide:
  - `github_oidc_provider_arn` and `github_repo` (from the bootstrap stack)
- Then set GitHub `prod` environment secret `AWS_ROLE_ARN` to the Terraform output:
  - `prod_summary.cicd.github_actions_role_arn`

This role is intentionally least-privilege (S3 artifacts + SSM rolling deploy only) and explicitly denies interactive Session Manager sessions.

## Notes

- PROD should not stop the database: stopping RDS breaks HA expectations and increases recovery risk; backups + Multi-AZ are the correct durability mechanisms.
- Observability is stricter than DEV: longer log retention and alarms on ALB target health.
