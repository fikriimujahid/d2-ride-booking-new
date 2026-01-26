#requires -Version 5.1

param(
  [ValidateSet('dev','prod')][string]$EnvName = 'dev',
  [ValidateSet('hcl','plan-json','state')][string]$Mode = '',
  [string]$Path = '',

  [switch]$GenerateHtmlReport,
  [int]$HtmlTop = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log([string]$Message) { Write-Host "[infracost] $Message" }
function Throw-Err([string]$Message) { throw "[infracost] ERROR: $Message" }

function Get-CiKind {
  if ($env:GITHUB_ACTIONS -eq 'true') { return 'github' }
  if ($env:GITLAB_CI) { return 'gitlab' }
  return 'local'
}

function Ensure-Infracost {
  if (Get-Command infracost -ErrorAction SilentlyContinue) {
    return
  }

  # Official Windows install method is Chocolatey.
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Throw-Err 'Infracost is not installed and Chocolatey (choco) was not found. Install choco or install Infracost manually: https://www.infracost.io/docs/#quick-start'
  }

  Write-Log "Installing Infracost via Chocolatey (ci=$(Get-CiKind))"
  choco install infracost -y | Out-Host
}

function Require-InfracostApiKey {
  if ([string]::IsNullOrWhiteSpace($env:INFRACOST_API_KEY)) {
    Throw-Err 'INFRACOST_API_KEY is not set. Store it in CI secrets (GitHub Actions secrets / GitLab CI variables) or set it in your shell.'
  }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TfEnvDir = Join-Path $RepoRoot "infra\terraform\envs\$EnvName"
$DefaultPlanJson = Join-Path $TfEnvDir 'plan.json'

if ([string]::IsNullOrWhiteSpace($Mode)) {
  if (Test-Path $DefaultPlanJson) { $Mode = 'plan-json' } else { $Mode = 'hcl' }
}

if ([string]::IsNullOrWhiteSpace($Path)) {
  switch ($Mode) {
    'hcl'      { $Path = $TfEnvDir }
    'plan-json' { $Path = $DefaultPlanJson }
    'state'    { $Path = $TfEnvDir }
    default    { Throw-Err "Invalid mode: $Mode" }
  }
}

Write-Log "CI: $(Get-CiKind)"
Write-Log "Env: $EnvName"
Write-Log "Mode: $Mode"
Write-Log "Path: $Path"

Require-InfracostApiKey
Ensure-Infracost

infracost --version | Out-Host

$OutJson = Join-Path $TfEnvDir 'infracost-breakdown.json'
$OutHtml = Join-Path $TfEnvDir 'infracost-report.html'
$ReportScript = Join-Path $PSScriptRoot 'infracost-report.ps1'

switch ($Mode) {
  'hcl' {
    infracost breakdown --path $Path --format table --show-skipped | Out-Host
    infracost breakdown --path $Path --format json --out-file $OutJson | Out-Host
  }
  'plan-json' {
    if (-not (Test-Path $Path)) {
      Throw-Err "Plan JSON not found: $Path. Generate it with: terraform plan -out plan.tfplan; terraform show -json plan.tfplan > plan.json"
    }
    infracost breakdown --path $Path --format table --show-skipped | Out-Host
    infracost breakdown --path $Path --format json --out-file $OutJson | Out-Host
  }
  'state' {
    # Read-only state-based estimate (requires backend access). May require AWS auth via OIDC/assumed role.
    infracost breakdown --path $Path --terraform-use-state --format table --show-skipped | Out-Host
    infracost breakdown --path $Path --terraform-use-state --format json --out-file $OutJson | Out-Host
  }
  default { Throw-Err "Invalid mode: $Mode" }
}

Write-Log "Wrote JSON output: $OutJson"

if ($GenerateHtmlReport) {
  if (-not (Test-Path -LiteralPath $ReportScript)) {
    Throw-Err "Report generator not found: $ReportScript"
  }
  if (-not (Test-Path -LiteralPath $OutJson)) {
    Throw-Err "Expected JSON output not found: $OutJson"
  }

  Write-Log "Generating HTML report: $OutHtml"
  & $ReportScript -EnvName $EnvName -InputJson $OutJson -OutputHtml $OutHtml -Top $HtmlTop
}
