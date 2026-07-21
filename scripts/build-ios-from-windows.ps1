# SpotiFLAC Enhanced - Build iOS IPA from Windows
# Uses GitHub Actions (free macOS runner) to build the IPA
# 
# Prerequisites: git, GitHub account, gh CLI (optional)

param(
    [ValidateSet('unsigned', 'appstore')]
    [string]$BuildType = 'unsigned'
)

$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path $PSScriptRoot -Parent

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  SpotiFLAC Enhanced - Build iOS IPA via GitHub Actions" -ForegroundColor Cyan
Write-Host "  Build type: $BuildType" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Check prerequisites ───────────────────────────

Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

$gitOk = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitOk) {
    Write-Host "ERROR: git not found. Install from https://git-scm.com" -ForegroundColor Red
    exit 1
}

$ghOk = Get-Command gh -ErrorAction SilentlyContinue

# ─── Step 2: Initialize git if needed ───────────────────────

Write-Host "[2/5] Checking git repository..." -ForegroundColor Yellow

Set-Location $ProjectDir

if (-not (Test-Path ".git")) {
    Write-Host "Initializing git repository..." -ForegroundColor Yellow
    git init
    git add .
    git commit -m "SpotiFLAC Enhanced: streaming + Apple Music UI"
}

$remoteUrl = git remote get-url origin 2>$null
if (-not $remoteUrl) {
    Write-Host ""
    Write-Host "No GitHub remote configured." -ForegroundColor Yellow
    Write-Host "You need to:"
    Write-Host "  1. Create a repo at https://github.com/new"
    Write-Host "  2. Run: git remote add origin https://github.com/YOUR_USER/spotiflac-enhanced.git"
    Write-Host ""
    
    if ($ghOk) {
        $createRepo = Read-Host "Create via gh CLI? (y/n)"
        if ($createRepo -eq 'y') {
            $repoName = Read-Host "Repo name (default: spotiflac-enhanced)"
            if (-not $repoName) { $repoName = 'spotiflac-enhanced' }
            gh repo create $repoName --public --source=. --push
        } else {
            exit 1
        }
    } else {
        exit 1
    }
}

# ─── Step 3: Commit all changes ─────────────────────────────

Write-Host "[3/5] Committing changes..." -ForegroundColor Yellow

$status = git status --porcelain
if ($status) {
    git add .
    git commit -m "feat(ios): streaming + preloading + Apple Music UI"
} else {
    Write-Host "  Nothing to commit." -ForegroundColor Gray
}

# ─── Step 4: Push to GitHub ─────────────────────────────────

Write-Host "[4/5] Pushing to GitHub..." -ForegroundColor Yellow
$branch = git branch --show-current
if (-not $branch) { $branch = 'main' }
git push -u origin $branch

# ─── Step 5: Trigger build ──────────────────────────────────

Write-Host "[5/5] Triggering GitHub Actions build..." -ForegroundColor Yellow

if ($ghOk) {
    gh workflow run build-ios.yml -f build_type=$BuildType --ref $branch
    
    Write-Host ""
    Write-Host "Build triggered! Monitoring..." -ForegroundColor Green
    Start-Sleep -Seconds 5
    
    $runId = gh run list --workflow=build-ios.yml --limit 1 --json databaseId --jq '.[0].databaseId'
    
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  BUILD TRIGGERED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  View progress:" -ForegroundColor White
    Write-Host "  https://github.com/$(git remote get-url origin | Select-String -Pattern 'github.com[:/](.+/.+)\.git').Matches.Groups[1]/actions/runs/$runId"
    Write-Host ""
    Write-Host "  gh run watch $runId" -ForegroundColor Gray
    
    # Optional: watch the build
    $watch = Read-Host "Watch build progress? (y/n)"
    if ($watch -eq 'y') {
        gh run watch $runId
        
        Write-Host ""
        Write-Host "Downloading IPA artifact..." -ForegroundColor Yellow
        gh run download $runId -n SpotiFLAC-unsigned-IPA -D "$ProjectDir\build\ios\"
        Write-Host "IPA downloaded to: build\ios\SpotiFLAC-unsigned.ipa" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  CODE PUSHED. Build IPA manually:" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1. Go to your repo on GitHub"
    Write-Host "  2. Click 'Actions' tab"
    Write-Host "  3. Click 'Build iOS IPA' workflow"
    Write-Host "  4. Click 'Run workflow' → select '$BuildType' → Run"
    Write-Host "  5. Wait ~15-20 min"
    Write-Host "  6. Download the IPA artifact"
    Write-Host ""
    Write-Host "  Install gh CLI for one-command build: winget install GitHub.cli" -ForegroundColor Gray
}
