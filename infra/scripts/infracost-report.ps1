#requires -Version 5.1

param(
  [Parameter(Mandatory = $false)][string]$InputJson = "",
  [Parameter(Mandatory = $false)][string]$OutputHtml = "",
  [Parameter(Mandatory = $false)][ValidateSet('dev','prod')][string]$EnvName = 'dev',
  [Parameter(Mandatory = $false)][int]$Top = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log([string]$Message) { Write-Host "[infracost] $Message" }
function Throw-Err([string]$Message) { throw "[infracost] ERROR: $Message" }

function HtmlEncode([string]$s) {
  if ($null -eq $s) { return '' }
  return [System.Net.WebUtility]::HtmlEncode($s)
}

function Get-Field($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [System.Collections.IDictionary]) { return $obj[$name] }
  return $obj.$name
}

function ToNumberOrNull($value) {
  if ($null -eq $value) { return $null }
  if ($value -is [double] -or $value -is [decimal] -or $value -is [int] -or $value -is [long]) { return [double]$value }
  $text = [string]$value
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  $result = 0.0
  if ([double]::TryParse($text, [ref]$result)) { return $result }
  return $null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultJson = Join-Path $repoRoot "infra\terraform\envs\$EnvName\infracost-breakdown.json"
$defaultHtml = Join-Path $repoRoot "infra\terraform\envs\$EnvName\infracost-report.html"

if ([string]::IsNullOrWhiteSpace($InputJson)) { $InputJson = $defaultJson }
if ([string]::IsNullOrWhiteSpace($OutputHtml)) { $OutputHtml = $defaultHtml }

if (-not (Test-Path -LiteralPath $InputJson)) {
  Throw-Err "Input JSON not found: $InputJson"
}

Write-Log "Reading: $InputJson"

$jsonText = Get-Content -LiteralPath $InputJson -Raw
# Windows PowerShell 5.1 does not support ConvertFrom-Json -Depth.
# Use .NET JavaScriptSerializer for deep JSON parsing.
Add-Type -AssemblyName System.Web.Extensions
$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$serializer.MaxJsonLength = 2147483647
$serializer.RecursionLimit = 200
$data = $serializer.DeserializeObject($jsonText)

$currency = Get-Field $data 'currency'
if ([string]::IsNullOrWhiteSpace($currency)) { $currency = 'USD' }

$timeGenerated = Get-Field $data 'timeGenerated'
$totalMonthlyCost = Get-Field $data 'totalMonthlyCost'
$totalHourlyCost = Get-Field $data 'totalHourlyCost'
$totalMonthlyUsageCost = Get-Field $data 'totalMonthlyUsageCost'

$summary = Get-Field $data 'summary'
$projects = @()
if ($null -ne (Get-Field $data 'projects')) { $projects = @((Get-Field $data 'projects')) }

# Flatten breakdown resources across projects
$allResources = @()
foreach ($p in $projects) {
  if ($null -eq $p) { continue }
  $projectName = Get-Field $p 'name'
  $resources = @()
  $breakdown = Get-Field $p 'breakdown'
  $breakdownResources = $null
  if ($null -ne $breakdown) { $breakdownResources = Get-Field $breakdown 'resources' }
  if ($null -ne $breakdownResources) { $resources = @($breakdownResources) }

  foreach ($r in $resources) {
    $monthly = ToNumberOrNull (Get-Field $r 'monthlyCost')
    $hourly = ToNumberOrNull (Get-Field $r 'hourlyCost')

    $components = @()
    $costComponents = Get-Field $r 'costComponents'
    if ($null -ne $costComponents) {
      foreach ($c in @($costComponents)) {
        $cMonthly = Get-Field $c 'monthlyCost'
        $cUsageBased = Get-Field $c 'usageBased'
        $cName = Get-Field $c 'name'
        if ($null -eq $cMonthly -and $cUsageBased -eq $true) {
          $components += ("{0} (usage-based)" -f $cName)
        } elseif ($null -ne $cMonthly) {
          $components += ("{0}: {1} {2}" -f $cName, $cMonthly, $currency)
        } else {
          $components += $cName
        }
      }
    }

    $allResources += [pscustomobject]@{
      Project     = $projectName
      Name        = Get-Field $r 'name'
      Type        = Get-Field $r 'resourceType'
      MonthlyCost = $monthly
      HourlyCost  = $hourly
      Components  = ($components -join '; ')
      Link        = Get-Field $r 'providerLink'
    }
  }
}

$topResources = $allResources |
  Where-Object { $null -ne $_.MonthlyCost } |
  Sort-Object -Property MonthlyCost -Descending |
  Select-Object -First $Top

$unsupportedCounts = Get-Field $summary 'unsupportedResourceCounts'
$noPriceCounts = Get-Field $summary 'noPriceResourceCounts'

function DictToHtmlTable($dict, [string]$title) {
  if ($null -eq $dict) { return "<p class='muted'>No data.</p>" }

  $rows = @()
  if ($dict -is [System.Collections.IDictionary]) {
    foreach ($k in ($dict.Keys | Sort-Object)) {
      $rows += "<tr><td>$(HtmlEncode ([string]$k))</td><td class='num'>$(HtmlEncode ([string]$dict[$k]))</td></tr>"
    }
  } else {
    foreach ($p in $dict.PSObject.Properties | Sort-Object Name) {
      $rows += "<tr><td>$(HtmlEncode $p.Name)</td><td class='num'>$(HtmlEncode ([string]$p.Value))</td></tr>"
    }
  }

  if ($rows.Count -eq 0) { return "<p class='muted'>No data.</p>" }

  return @"
<h3>$(HtmlEncode $title)</h3>
<table>
  <thead><tr><th>Resource type</th><th class='num'>Count</th></tr></thead>
  <tbody>
    $($rows -join "`n    ")
  </tbody>
</table>
"@
}

$resourceRows = @()
foreach ($r in $topResources) {
  $m = if ($null -ne $r.MonthlyCost) { "{0:N2}" -f $r.MonthlyCost } else { "" }
  $h = if ($null -ne $r.HourlyCost) { "{0:N4}" -f $r.HourlyCost } else { "" }

  $resourceRows += @"
<tr>
  <td>$(HtmlEncode $r.Project)</td>
  <td><code>$(HtmlEncode $r.Type)</code></td>
  <td><code>$(HtmlEncode $r.Name)</code></td>
  <td class='num'>$m</td>
  <td class='num'>$h</td>
  <td class='muted'>$(HtmlEncode $r.Components)</td>
</tr>
"@
}

$resourceTable = if ($resourceRows.Count -gt 0) {
@"
<h2>Top $Top resources by monthly cost</h2>
<table>
  <thead>
    <tr>
      <th>Project</th>
      <th>Type</th>
      <th>Name</th>
      <th class='num'>Monthly ($currency)</th>
      <th class='num'>Hourly ($currency)</th>
      <th>Notes</th>
    </tr>
  </thead>
  <tbody>
    $($resourceRows -join "`n")
  </tbody>
</table>
"@
} else {
  "<p class='muted'>No costed resources found (all resources may be usage-based or unsupported).</p>"
}

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Infracost report - $EnvName</title>
  <style>
    :root { --bg:#0b1220; --panel:#0f1a2e; --text:#e6edf7; --muted:#9fb0c6; --accent:#7aa2ff; --border:#22314d; }
    body { margin:0; font-family: Segoe UI, Roboto, Arial, sans-serif; background:var(--bg); color:var(--text); }
    .wrap { max-width: 1200px; margin: 0 auto; padding: 28px; }
    .header { display:flex; justify-content:space-between; align-items:flex-end; gap:16px; }
    h1 { margin:0; font-size: 22px; }
    .meta { color: var(--muted); font-size: 13px; }
    .cards { display:grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin-top: 16px; }
    .card { background: var(--panel); border:1px solid var(--border); border-radius: 10px; padding: 14px; }
    .card .label { color: var(--muted); font-size: 12px; }
    .card .value { font-size: 20px; margin-top: 6px; }
    a { color: var(--accent); }
    table { width:100%; border-collapse: collapse; margin-top: 12px; background: var(--panel); border:1px solid var(--border); border-radius: 10px; overflow:hidden; }
    th, td { padding: 10px 12px; border-bottom: 1px solid var(--border); vertical-align: top; }
    th { text-align: left; color: var(--muted); font-weight: 600; background: rgba(255,255,255,0.02); }
    tr:last-child td { border-bottom: none; }
    .num { text-align: right; white-space: nowrap; }
    .muted { color: var(--muted); }
    code { font-family: Consolas, ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
    h2 { margin-top: 22px; font-size: 16px; }
    h3 { margin-top: 18px; font-size: 14px; color: var(--muted); }
    .note { margin-top: 12px; color: var(--muted); font-size: 13px; }
    @media (max-width: 900px) { .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <div>
        <h1>Infracost report ($EnvName)</h1>
        <div class="meta">Generated: $(HtmlEncode ([string]$timeGenerated))</div>
        <div class="meta">Source: $(HtmlEncode $InputJson)</div>
      </div>
      <div class="meta">Currency: $(HtmlEncode $currency)</div>
    </div>

    <div class="cards">
      <div class="card"><div class="label">Total monthly cost</div><div class="value">$currency $(HtmlEncode ([string]$totalMonthlyCost))</div></div>
      <div class="card"><div class="label">Total hourly cost</div><div class="value">$currency $(HtmlEncode ([string]$totalHourlyCost))</div></div>
      <div class="card"><div class="label">Monthly usage-based cost</div><div class="value">$currency $(HtmlEncode ([string]$totalMonthlyUsageCost))</div></div>
      <div class="card"><div class="label">Detected resources</div><div class="value">$(HtmlEncode ([string]$summary.totalDetectedResources))</div></div>
    </div>

    <div class="cards">
      <div class="card"><div class="label">Supported resources</div><div class="value">$(HtmlEncode ([string]$summary.totalSupportedResources))</div></div>
      <div class="card"><div class="label">Unsupported resources</div><div class="value">$(HtmlEncode ([string]$summary.totalUnsupportedResources))</div></div>
      <div class="card"><div class="label">Usage-based resources</div><div class="value">$(HtmlEncode ([string]$summary.totalUsageBasedResources))</div></div>
      <div class="card"><div class="label">No-price resources</div><div class="value">$(HtmlEncode ([string]$summary.totalNoPriceResources))</div></div>
    </div>

    $resourceTable

    <h2>Coverage details</h2>
    $(DictToHtmlTable $unsupportedCounts 'Unsupported resource types')
    $(DictToHtmlTable $noPriceCounts 'Resources with no direct price')

    <p class="note">
      Notes: resources marked as “usage-based” (e.g., data transfer, requests, LCU) need usage estimates to produce non-zero monthly costs.
    </p>
  </div>
</body>
</html>
"@

$null = New-Item -ItemType Directory -Path (Split-Path -Parent $OutputHtml) -Force
Set-Content -LiteralPath $OutputHtml -Value $html -Encoding UTF8

Write-Log "Wrote HTML report: $OutputHtml"
Write-Log "Open it in a browser (or run): Start-Process -FilePath $OutputHtml"
