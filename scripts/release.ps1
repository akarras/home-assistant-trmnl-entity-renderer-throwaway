# Release script for Home Assistant TRMNL Entity Renderer (PowerShell version)
# This script helps create version tags that trigger GitHub Actions

param(
    [string]$Version,
    [switch]$Force
)

# Function to print colored output
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

# Check if we're in the right directory
if (-not (Test-Path "Cargo.toml")) {
    Write-Error "This script must be run from the project root directory"
    exit 1
}

# Check if git is clean
$gitStatus = git status --porcelain
if ($gitStatus -and -not $Force) {
    Write-Error "Git working directory is not clean. Please commit or stash your changes."
    git status --short
    exit 1
}

# Check if we're on main/master branch
$currentBranch = git branch --show-current
if ($currentBranch -notin @("main", "master") -and -not $Force) {
    Write-Warning "You are not on the main/master branch (current: $currentBranch)"
    $continue = Read-Host "Do you want to continue? (y/N)"
    if ($continue -notmatch "^[Yy]$") {
        Write-Info "Release cancelled."
        exit 0
    }
}

# Get current version from Cargo.toml
$cargoContent = Get-Content "Cargo.toml"
$currentVersion = ($cargoContent | Select-String '^version = "(.*)"').Matches[0].Groups[1].Value
Write-Info "Current version: $currentVersion"

# Determine new version
if ($Version) {
    $newVersion = $Version
    if ($newVersion -notmatch '^\d+\.\d+\.\d+$') {
        Write-Error "Invalid version format. Please use semantic versioning (e.g., 1.2.3)"
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "Release types:"
    Write-Host "  1) Patch release (e.g., 1.0.0 -> 1.0.1)"
    Write-Host "  2) Minor release (e.g., 1.0.1 -> 1.1.0)"
    Write-Host "  3) Major release (e.g., 1.1.0 -> 2.0.0)"
    Write-Host "  4) Custom version"
    Write-Host ""

    $releaseType = Read-Host "Select release type (1-4)"

    $versionParts = $currentVersion.Split('.')
    $major = [int]$versionParts[0]
    $minor = [int]$versionParts[1]
    $patch = [int]$versionParts[2]

    switch ($releaseType) {
        "1" {
            # Patch release
            $newVersion = "$major.$minor.$($patch + 1)"
        }
        "2" {
            # Minor release
            $newVersion = "$major.$($minor + 1).0"
        }
        "3" {
            # Major release
            $newVersion = "$($major + 1).0.0"
        }
        "4" {
            # Custom version
            $newVersion = Read-Host "Enter new version (e.g., 1.2.3)"
            if ($newVersion -notmatch '^\d+\.\d+\.\d+$') {
                Write-Error "Invalid version format. Please use semantic versioning (e.g., 1.2.3)"
                exit 1
            }
        }
        default {
            Write-Error "Invalid selection"
            exit 1
        }
    }
}

Write-Info "New version will be: $newVersion"

# Confirm release
if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Create release v$newVersion? (y/N)"
    if ($confirm -notmatch "^[Yy]$") {
        Write-Info "Release cancelled."
        exit 0
    }
}

# Update version in Cargo.toml
Write-Info "Updating Cargo.toml version..."
$cargoContent = $cargoContent -replace '^version = ".*"', "version = `"$newVersion`""
$cargoContent | Set-Content "Cargo.toml"

# Update Cargo.lock
Write-Info "Updating Cargo.lock..."
cargo check | Out-Null

# Commit version bump
Write-Info "Committing version bump..."
git add Cargo.toml Cargo.lock
git commit -m "chore: bump version to v$newVersion"

# Create tag message
$tagMessage = @"
Release version $newVersion

Features:
- TRMNL display support (800x480, 1-bit grayscale)
- Multi-sensor status images with visual gauges
- Large text optimized for distance viewing
- Docker support with multi-architecture builds

Docker:
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:v$newVersion
"@

# Create and push tag
Write-Info "Creating git tag v$newVersion..."
git tag -a "v$newVersion" -m $tagMessage

# Push changes and tag
Write-Info "Pushing changes and tag to remote..."
git push origin $currentBranch
git push origin "v$newVersion"

Write-Success "Release v$newVersion created successfully!"
Write-Host ""
Write-Info "GitHub Actions will now:"
Write-Info "  • Build Docker images for multiple architectures"
Write-Info "  • Create GitHub release with binaries"
Write-Info "  • Publish to GitHub Container Registry"
Write-Host ""
Write-Info "Monitor the release at:"
Write-Info "  https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway/releases"
Write-Info "  https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway/actions"
Write-Host ""
Write-Info "Docker image will be available at:"
Write-Info "  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:v$newVersion"
Write-Info "  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest"
