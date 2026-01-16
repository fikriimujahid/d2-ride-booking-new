# ride-booking-platform (Phase 1)

Demo-grade, production-credible monorepo foundation for an Uber-like ride booking platform.

Phase 1 scope: **source control + DEV-first CI + security scanning**.

## Repo structure

```
apps/
  backend-api/        # NestJS
  web-admin/          # React + Vite
  web-passenger/      # Next.js (static export)
  web-driver/         # Next.js (SSR / WebSocket ready)
infra/
  terraform/
    modules/
    envs/
      dev/
      prod/
docs/
  architecture.md
  auth-cognito.md
  cost-strategy.md
.github/workflows/
  ci-backend.yml
  ci-web-admin.yml
  ci-web-passenger.yml
  ci-web-driver.yml
  ci-infra.yml
```

## Branching strategy

- `dev`: active development
- `main`: production-ready (no deployment in Phase 1)

Rules (enforced by process + CI):

- CI runs on **pull requests targeting `dev`**.
- No direct commits to `main` (configure GitHub Branch Protection on `main`: require PRs, disallow force-push, require CI).

## CI / DevSecOps (DEV-only)

GitHub Actions workflows are **path-filtered** so only relevant pipelines run.

- Backend: lint, unit tests, build, `npm audit`, Semgrep (SAST)
- Frontends: typecheck, lint, build, `npm audit`, Semgrep (SAST)
- Infra: `terraform fmt` and `terraform validate` only (no `apply`)

No AWS credentials are used and **no deployment happens** in Phase 1.

## Local dev quickstart

Backend:

```powershell
cd apps\backend-api
npm install
npm run test
npm run build
```

Web Admin:

```powershell
cd apps\web-admin
npm install
npm run typecheck
npm run build
```

Web Passenger:

```powershell
cd apps\web-passenger
npm install
npm run build
```

Web Driver:

```powershell
cd apps\web-driver
npm install
npm run build
```

Terraform (validate-only):

```powershell
cd infra\terraform\envs\dev
terraform init -backend=false
terraform validate
```

See docs:

- [docs/architecture.md](docs/architecture.md)
- [docs/auth-cognito.md](docs/auth-cognito.md)
- [docs/cost-strategy.md](docs/cost-strategy.md)
