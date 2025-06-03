@echo off
setlocal enabledelayedexpansion

:: Home Assistant Image Server Startup Script for Windows
:: This script helps you start the server with proper environment setup

echo 🚀 Home Assistant Image Server Startup Script
echo.

:: Check if .env file exists
if not exist ".env" (
    echo ⚠️  No .env file found. Creating one from template...

    if exist ".env.example" (
        copy ".env.example" ".env" >nul
        echo ✅ Created .env from .env.example
        echo 📝 Please edit .env file with your Home Assistant details:
        echo    - HA_URL: Your Home Assistant URL
        echo    - HA_TOKEN: Your Long-Lived Access Token
        echo.
        echo Press Enter to continue after editing .env, or Ctrl+C to exit...
        pause >nul
    ) else (
        echo ❌ No .env.example file found!
        echo Creating basic .env file...
        (
            echo # Home Assistant Configuration
            echo HA_URL=http://localhost:8123
            echo HA_TOKEN=your_long_lived_access_token_here
            echo.
            echo # Server Configuration
            echo PORT=3000
            echo.
            echo # Logging Level
            echo RUST_LOG=info
        ) > .env
        echo ✅ Basic .env file created
        echo 📝 Please edit .env file with your Home Assistant details
        echo.
        echo To get your Home Assistant token:
        echo 1. Go to Home Assistant ^> Profile ^> Long-Lived Access Tokens
        echo 2. Create Token ^> Copy the token
        echo 3. Update HA_TOKEN in .env file
        echo.
        pause
        exit /b 1
    )
)

:: Check if Cargo is installed
where cargo >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Cargo ^(Rust^) not found!
    echo Please install Rust from: https://rustup.rs/
    pause
    exit /b 1
)

echo 📋 Environment will be loaded from .env file automatically
echo.

:: Get port from .env file or use default
set PORT=3000
for /f "tokens=1,2 delims==" %%a in ('type .env 2^>nul ^| findstr "^PORT="') do (
    set PORT=%%b
)

echo 🔨 Building and starting the server...
echo 📍 Server will be available at: http://localhost:!PORT!
echo 🧪 Test page available at: file://%cd%\test.html
echo.
echo Press Ctrl+C to stop the server
echo.

:: Start the server
cargo run

:: This should not be reached due to Ctrl+C, but just in case
echo.
echo 🛑 Server stopped
pause
