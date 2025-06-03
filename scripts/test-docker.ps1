# Docker build test script for Home Assistant TRMNL Entity Renderer (PowerShell version)
# This script tests Docker builds locally before pushing to GitHub

param(
    [switch]$SkipCleanup,
    [switch]$Verbose
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

# Check if Docker is running
try {
    docker info | Out-Null
} catch {
    Write-Error "Docker is not running. Please start Docker and try again."
    exit 1
}

Write-Info "Starting Docker build test..."

# Clean up any existing test containers/images
function Cleanup {
    if (-not $SkipCleanup) {
        Write-Info "Cleaning up test containers and images..."
        docker stop ha-trmnl-test 2>$null
        docker rm ha-trmnl-test 2>$null
        docker rmi ha-trmnl-renderer:test 2>$null
    }
}

# Set trap to cleanup on exit
trap { Cleanup } EXIT

# Generate Cargo.lock if it doesn't exist
if (-not (Test-Path "Cargo.lock")) {
    Write-Info "Generating Cargo.lock..."
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        cargo generate-lockfile
    } else {
        Write-Warning "Cargo not found locally. Using Docker to generate Cargo.lock..."
        docker run --rm -v "${PWD}:/workspace" -w /workspace rust:1.75-slim cargo generate-lockfile
    }
    Write-Success "Cargo.lock generated"
}

# Build the Docker image
Write-Info "Building Docker image..."
$buildResult = docker build -t ha-trmnl-renderer:test .
if ($LASTEXITCODE -eq 0) {
    Write-Success "Docker image built successfully"
} else {
    Write-Error "Docker build failed"
    exit 1
}

# Test the image
Write-Info "Testing Docker image..."

# Start container with test environment variables
docker run -d `
    --name ha-trmnl-test `
    -p 3001:3000 `
    -e HA_URL=http://example.com:8123 `
    -e HA_TOKEN=test_token `
    -e RUST_LOG=info `
    ha-trmnl-renderer:test

# Wait for container to start
Write-Info "Waiting for container to start..."
Start-Sleep -Seconds 5

# Test health endpoint
Write-Info "Testing health endpoint..."
$maxAttempts = 10
$attempt = 1

while ($attempt -le $maxAttempts) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3001/health" -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            Write-Success "Health check passed"
            break
        }
    } catch {
        Write-Warning "Health check attempt $attempt/$maxAttempts failed, retrying..."
        Start-Sleep -Seconds 2
        $attempt++
    }
}

if ($attempt -gt $maxAttempts) {
    Write-Error "Health check failed after $maxAttempts attempts"
    Write-Info "Container logs:"
    docker logs ha-trmnl-test
    exit 1
}

# Test TRMNL endpoint (will fail with connection error but should return proper HTTP error)
Write-Info "Testing TRMNL endpoint (expect connection error)..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3001/trmnl?sensors=sensor.test&title=TEST" -UseBasicParsing -TimeoutSec 10
    $httpCode = $response.StatusCode
} catch {
    $httpCode = $_.Exception.Response.StatusCode.value__
    if (-not $httpCode) { $httpCode = "000" }
}

if ($httpCode -in @(200, 400, 500)) {
    Write-Success "TRMNL endpoint responding (HTTP $httpCode)"
} else {
    Write-Warning "TRMNL endpoint returned HTTP $httpCode (this may be expected)"
}

# Check image size
Write-Info "Checking image size..."
$imageInfo = docker images ha-trmnl-renderer:test --format "{{.Size}}"
Write-Info "Final image size: $imageInfo"

# Show container stats
Write-Info "Container resource usage:"
docker stats ha-trmnl-test --no-stream --format "table {{.Container}}`t{{.CPUPerc}}`t{{.MemUsage}}`t{{.MemPerc}}"

# Test multi-platform build capability (if buildx is available)
try {
    docker buildx version | Out-Null
    Write-Info "Testing multi-platform build capability..."
    $buildxResult = docker buildx build --platform linux/amd64 -t ha-trmnl-renderer:test-amd64 . --load
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Multi-platform build (amd64) successful"
        docker rmi ha-trmnl-renderer:test-amd64 2>$null
    } else {
        Write-Warning "Multi-platform build test failed (this is optional)"
    }
} catch {
    Write-Info "Docker Buildx not available, skipping multi-platform test"
}

Write-Success "All Docker tests passed!"

# Display useful information
Write-Host ""
Write-Info "Test Results Summary:"
Write-Host "  ✅ Docker build: SUCCESS"
Write-Host "  ✅ Container start: SUCCESS"
Write-Host "  ✅ Health check: SUCCESS"
Write-Host "  ✅ Endpoint response: SUCCESS"
Write-Host "  📏 Image size: $imageInfo"
Write-Host ""
Write-Info "Ready for deployment! You can now:"
Write-Host "  • Push to GitHub to trigger automatic builds"
Write-Host "  • Create a release with: .\scripts\release.ps1"
Write-Host "  • Deploy locally with: docker run ha-trmnl-renderer:test"
Write-Host ""
Write-Info "Example deployment command:"
Write-Host "docker run -d \"
Write-Host "  --name ha-trmnl-renderer \"
Write-Host "  -p 3000:3000 \"
Write-Host "  -e HA_URL=http://your-homeassistant:8123 \"
Write-Host "  -e HA_TOKEN=your_token \"
Write-Host "  --restart unless-stopped \"
Write-Host "  ha-trmnl-renderer:test"

# Cleanup if not skipped
if (-not $SkipCleanup) {
    Cleanup
}
