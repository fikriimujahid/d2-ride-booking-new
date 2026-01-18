# ============================================================================
# DEV INFRASTRUCTURE DIAGRAM (INFRAMAP)
# ============================================================================
# This script generates a human-readable architecture diagram for the DEV
# environment only. It uses Terraform inputs/state and Inframap to create
# a DOT file and then renders SVG + PNG via Graphviz.
#
# VALIDATION CHECKLIST (COMMENTS):
# - Diagram shows VPC, subnets, RDS, EC2 roles, security groups
# - Diagram generation is repeatable
# - No infrastructure changes occur
# - Diagram is suitable for README or presentation
# ============================================================================

$ErrorActionPreference = "Stop"

$RootDir = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$TfDir = Join-Path $RootDir "infra\terraform\envs\dev"
$OutDir = Join-Path $RootDir "docs\diagrams"
$DotOut = Join-Path $OutDir "dev-infra.dot"
$SvgOut = Join-Path $OutDir "dev-infra.svg"
$PngOut = Join-Path $OutDir "dev-infra.png"

# Ensure output directory exists
if (!(Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

# Check for Terraform
if (!(Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Error "Error: terraform is not installed or not in PATH."
    exit 1
}

# Check for Inframap
$InframapBin = $null
if (Get-Command inframap -ErrorAction SilentlyContinue) {
    $InframapBin = (Get-Command inframap).Source
} else {
    Write-Error "Error: inframap is not installed or not in PATH."
    Write-Host "To install inframap, run: go install github.com/cycloidio/inframap@latest"
    exit 1
}

# Check for Graphviz dot
$DotBin = $null
if (Get-Command dot -ErrorAction SilentlyContinue) {
    $DotBin = (Get-Command dot).Source
} elseif (Test-Path "C:\Program Files\Graphviz\bin\dot.exe") {
    $DotBin = "C:\Program Files\Graphviz\bin\dot.exe"
}

Write-Host "============================================================================"
Write-Host "GENERATING DEV ENVIRONMENT DIAGRAM"
Write-Host "============================================================================"
Write-Host "Terraform dir: $TfDir"
Write-Host "Output dir:    $OutDir"
Write-Host ""

# Terraform init: safe, no apply, no AWS credentials required.
Write-Host "[1/3] Running terraform init (safe, no apply)..."
Push-Location $TfDir
terraform init -backend=false -input=false | Out-Null
Write-Host "      checkmark Terraform initialized"
Pop-Location

# Generate DOT file using Inframap
Write-Host ""
Write-Host "[2/3] Generating DOT file via Inframap..."

# Generate from tfstate with provider-specific visualization (icons, grouping)
# Official docs: inframap generate state.tfstate | dot -Tpng > graph.png
# Using --clean=false to show all nodes including unconnected ones (with icons)
$TfStateFile = Join-Path $TfDir "terraform.tfstate"
if (Test-Path $TfStateFile) {
    # Use ASCII encoding to avoid UTF-8 BOM which causes Graphviz "strict" syntax error
    & $InframapBin generate "$TfStateFile" --clean=false | Out-File -FilePath $DotOut -Encoding ASCII
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to generate DOT file from Inframap"
        exit 1
    }
    Write-Host "      checkmark Generated DOT from TFState with icons: $DotOut"
} else {
    Write-Error "No terraform.tfstate found at $TfStateFile. Please run 'terraform apply' first."
    Write-Host "  Alternative: Use 'inframap generate <directory>' for HCL files (requires module init)"
    exit 1
}

# Render SVG and PNG using Graphviz
Write-Host ""
Write-Host "[3/3] Rendering SVG and PNG..."
if ($DotBin) {
    # Render SVG
    $svgResult = & $DotBin -Tsvg "$DotOut" -o "$SvgOut" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      checkmark Rendered SVG: $SvgOut"
    } else {
        Write-Host "      warning SVG rendering had warnings: $svgResult" -ForegroundColor Yellow
        if (Test-Path $SvgOut) {
            Write-Host "      checkmark SVG file created despite warnings: $SvgOut"
        }
    }
    
    # Render PNG
    $pngResult = & $DotBin -Tpng "$DotOut" -o "$PngOut" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      checkmark Rendered PNG: $PngOut"
    } else {
        Write-Host "      warning PNG rendering had warnings: $pngResult" -ForegroundColor Yellow
        if (Test-Path $PngOut) {
            Write-Host "      checkmark PNG file created despite warnings: $PngOut"
        }
    }
} else {
    Write-Host "      warning Graphviz 'dot' not found. SVG/PNG not generated."
    Write-Host "        To install Graphviz: https://graphviz.org/download/"
}

Write-Host ""
Write-Host "============================================================================"
Write-Host "checkmark DIAGRAM GENERATION COMPLETE"
Write-Host "============================================================================"
Write-Host "Generated files:"
Write-Host "  - DOT: $DotOut"
if ($DotBin) {
    Write-Host "  - SVG: $SvgOut"
    Write-Host "  - PNG: $PngOut"
}
Write-Host ""
Write-Host "View the diagram:"
Write-Host "  - Open $SvgOut in your browser"
Write-Host "  - Or open $PngOut in any image viewer"
Write-Host ""
