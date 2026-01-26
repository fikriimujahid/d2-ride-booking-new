# Infracost cost estimation (Terraform)

This repo uses **Infracost** to generate monthly cost estimates for Terraform-based AWS infrastructure.

## What this does (and does not do)

- ✅ Produces **monthly cost estimates** and **per-resource breakdowns**.
- ✅ Works in CI/CD using **OIDC IAM roles** (no static AWS access keys).
- ✅ Uses the **Infracost Cloud Pricing API** via `INFRACOST_API_KEY`.
- ✅ Does **not** apply Terraform or modify live infrastructure.
- ⚠️ If you run Terraform plan/state-based workflows, Terraform may still need AWS auth to read:
  - remote backends (e.g., S3 state)
  - data sources (e.g., `aws_ami`, `aws_ssm_parameter`, etc.)

## How pricing data is retrieved

Infracost calculates costs locally by parsing Terraform (or a plan JSON). It then queries the **Infracost Cloud Pricing API** for unit prices using `INFRACOST_API_KEY`.

- No static AWS credentials are required for pricing.
- No Terraform secrets or cloud credentials are sent to the pricing API.

## Required secrets

- `INFRACOST_API_KEY` (CI secret / variable)
  - GitHub Actions: repository secret `INFRACOST_API_KEY`
  - GitLab CI: masked variable `INFRACOST_API_KEY`

## Local usage

### Option A (recommended): estimate from Terraform code (HCL)

This is fast and doesn’t require `terraform plan`.

- PowerShell:
  - `\infra\scripts\infracost-estimate.ps1 -EnvName dev -Mode hcl`
  - With HTML report: `\infra\scripts\infracost-estimate.ps1 -EnvName dev -Mode hcl -GenerateHtmlReport -HtmlTop 30`
- Bash:
  - `./infra/scripts/infracost-estimate.sh --env dev --mode hcl`

### Option B: estimate from Terraform plan JSON

If you already have a plan JSON:

- PowerShell:
  - `\infra\scripts\infracost-estimate.ps1 -EnvName dev -Mode plan-json -Path \infra\terraform\envs\dev\plan.json`
- Bash:
  - `./infra/scripts/infracost-estimate.sh --env dev --mode plan-json --path infra/terraform/envs/dev/plan.json`

### Option C: estimate from Terraform state (read-only)

- PowerShell:
  - `\infra\scripts\infracost-estimate.ps1 -EnvName dev -Mode state`
- Bash:
  - `./infra/scripts/infracost-estimate.sh --env dev --mode state`

This may require AWS auth for the remote state backend (use SSO or assumed-role; do not use long-lived access keys).

## CI/CD integration

### GitHub Actions

The workflow [ .github/workflows/infra-terraform-ci-dev.yml ] runs:

- `terraform plan` → `plan.json`
- `infracost breakdown` (table + JSON)
- `infracost diff` (JSON)
- Optional PR comment via `infracost comment github`

Ensure `INFRACOST_API_KEY` is set as a GitHub Actions secret.

### GitLab CI (example snippet)

```yaml
infracost:
  image: alpine:3.20
  stage: test
  variables:
    TF_IN_AUTOMATION: "true"
  script:
    - apk add --no-cache bash curl git
    - curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
    - infracost --version
    - test -n "$INFRACOST_API_KEY" || (echo "INFRACOST_API_KEY missing" >&2; exit 1)

    # If you already generate a plan.json in CI, point Infracost at it:
    - infracost breakdown --path infra/terraform/envs/dev/plan.json --format table --show-skipped
    - infracost diff --path infra/terraform/envs/dev/plan.json --format table --show-skipped

  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

If you want merge request comments, generate JSON (`--format json --out-file infracost.json`) and use `infracost comment gitlab ...`.

## Example output

Breakdown output (table format) looks like:

- Total monthly cost and per-resource line items
- `Project: <name>` with `Monthly cost`, `Qty`, and `Unit cost`

For PR diffs, `infracost comment` posts a Markdown table showing:

- Previous monthly cost
- New monthly cost
- Monthly cost delta

## Limitations / notes

- Usage-based costs (e.g., egress data transfer, Lambda invocations) require explicit usage estimates; otherwise they may be **missing or shown as $0**.
- Some resources have **partial** cost coverage depending on provider support.
- Taxes, negotiated discounts, Savings Plans/RIs, and org-specific billing constructs may not be reflected.
- A Terraform plan can still evaluate data sources; keep `-refresh=false` in automation if you want to avoid querying live infra.
