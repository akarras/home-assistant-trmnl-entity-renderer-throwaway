# Home Assistant Image Server Startup Script for PowerShell
# This script helps you start the server with proper environment setup

param(
    [string]$Port = "3000",
    [switch]$Debug,
    [switch]$Help
)

if ($Help) {
    Write-Host "Home Assistant Image Server Startup Script" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Usage: .\run.ps1 [-Port <port>] [-Debug] [-Help]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Green
    Write-Host "  -Port <port>  : Specify port number (default: 3000)"
    Write-Host "  -Debug        : Enable debug logging"
    Write-Host "  -Help         : Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\run.ps1                 # Start with default settings"
    Write-Host "  .\run.ps1 -Port 8080      # Start on port 8080"
    Write-Host "  .\run.ps1 -Debug          # Start with debug logging"
    exit 0
}

Write-Host "🚀 Home Assistant Image Server Startup Script" -ForegroundColor Blue
Write-Host ""

# Function to write colored output
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# Check if .env file exists
if (-not (Test-Path ".env")) {
    Write-ColorOutput "⚠️  No .env file found. Creating one from template..." "Yellow"

    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-ColorOutput "✅ Created .env from .env.example" "Green"
        Write-ColorOutput "📝 Please edit .env file with your Home Assistant details:" "Yellow"
        Write-ColorOutput "   - HA_URL: Your Home Assistant URL" "Yellow"
        Write-ColorOutput "   - HA_TOKEN: Your Long-Lived Access Token" "Yellow"
        Write-Host ""
        Write-ColorOutput "Press Enter to continue after editing .env, or Ctrl+C to exit..." "Yellow"
        Read-Host
    } else {
        Write-ColorOutput "❌ No .env.example file found!" "Red"
        Write-ColorOutput "Creating basic .env file..." "Yellow"

        $envContent = @"
# Home Assistant Configuration
HA_URL=http://localhost:8123
HA_TOKEN=your_long_lived_access_token_here

# Server Configuration
PORT=3000

# Logging Level
RUST_LOG=info
"@
        $envContent | Out-File -FilePath ".env" -Encoding UTF8

        Write-ColorOutput "✅ Basic .env file created" "Green"
        Write-ColorOutput "📝 Please edit .env file with your Home Assistant details" "Yellow"
        Write-Host ""
        Write-ColorOutput "To get your Home Assistant token:" "Cyan"
        Write-ColorOutput "1. Go to Home Assistant > Profile > Long-Lived Access Tokens" "Cyan"
        Write-ColorOutput "2. Create Token > Copy the token" "Cyan"
        Write-ColorOutput "3. Update HA_TOKEN in .env file" "Cyan"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Check if Cargo is installed
try {
    $null = Get-Command cargo -ErrorAction Stop
    Write-ColorOutput "✅ Cargo (Rust) found" "Green"
} catch {
    Write-ColorOutput "❌ Cargo (Rust) not found!" "Red"
    Write-ColorOutput "Please install Rust from: https://rustup.rs/" "Yellow"
    Read-Host "Press Enter to exit"
    exit 1
}

# Load and validate .env file
Write-ColorOutput "📋 Loading environment from .env file..." "Blue"
$envVars = @{}

if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^#][^=]+)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $envVars[$key] = $value
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

# Override port if specified
if ($Port -ne "3000") {
    $envVars["PORT"] = $Port
    [Environment]::SetEnvironmentVariable("PORT", $Port, "Process")
}

# Set debug logging if requested
if ($Debug) {
    $envVars["RUST_LOG"] = "debug"
    [Environment]::SetEnvironmentVariable("RUST_LOG", "debug", "Process")
}

# Validate required environment variables
$haUrl = $env:HA_URL
$haToken = $env:HA_TOKEN

if (-not $haUrl -or $haUrl -eq "your_home_assistant_url_here") {
    Write-ColorOutput "❌ HA_URL not set in .env file" "Red"
    exit 1
}

if (-not $haToken -or $haToken -eq "your_long_lived_access_token_here") {
    Write-ColorOutput "❌ HA_TOKEN not set in .env file" "Red"
    Write-ColorOutput "To get your token:" "Yellow"
    Write-ColorOutput "1. Go to Home Assistant > Profile > Long-Lived Access Tokens" "Yellow"
    Write-ColorOutput "2. Create Token > Copy the token" "Yellow"
    Write-ColorOutput "3. Update HA_TOKEN in .env file" "Yellow"
    exit 1
}

Write-ColorOutput "✅ Environment configured:" "Green"
Write-ColorOutput "   HA_URL: $haUrl" "Blue"
Write-ColorOutput "   HA_TOKEN: $($haToken.Substring(0, [Math]::Min(10, $haToken.Length)))..." "Blue"
Write-ColorOutput "   PORT: $($env:PORT)" "Blue"
Write-ColorOutput "   RUST_LOG: $($env:RUST_LOG)" "Blue"
Write-Host ""

# Test Home Assistant connection if possible
Write-ColorOutput "🔍 Testing Home Assistant connection..." "Blue"
try {
    $headers = @{
        "Authorization" = "Bearer $haToken"
        "Content-Type" = "application/json"
    }

    $response = Invoke-WebRequest -Uri "$haUrl/api/" -Headers $headers -TimeoutSec 10 -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-ColorOutput "✅ Home Assistant is reachable" "Green"
    }
} catch {
    Write-ColorOutput "⚠️  Warning: Could not reach Home Assistant at $haUrl" "Yellow"
    Write-ColorOutput "   Server will still start, but image serving may not work" "Yellow"
    Write-ColorOutput "   Error: $($_.Exception.Message)" "Yellow"
}

Write-Host ""

# Set up cleanup function
$cleanup = {
    Write-Host ""
    Write-ColorOutput "🛑 Shutting down server..." "Yellow"
    exit 0
}

# Register cleanup for Ctrl+C
[Console]::CancelKeyPress += $cleanup

# Build and run the server
Write-ColorOutput "🔨 Building and starting the server..." "Blue"
Write-ColorOutput "📍 Server will be available at: http://localhost:$($env:PORT)" "Blue"
Write-ColorOutput "🧪 Test page available at: file://$(Get-Location)\test.html" "Blue"
Write-Host ""
Write-ColorOutput "Press Ctrl+C to stop the server" "Yellow"
Write-Host ""

# Check if this is the first run
if (-not (Test-Path "target")) {
    Write-ColorOutput "🔄 First run detected. This may take a few minutes to download and compile dependencies..." "Cyan"
    Write-Host ""
}

try {
    # Start the server
    & cargo run
} catch {
    Write-ColorOutput "❌ Failed to start server: $($_.Exception.Message)" "Red"
    Read-Host "Press Enter to exit"
    exit 1
}

# This should not be reached due to Ctrl+C handler, but just in case
Write-ColorOutput "🛑 Server stopped" "Yellow"
Read-Host "Press Enter to exit"
