@echo off
setlocal enabledelayedexpansion

:: Simple Image Server Test Script for Windows
:: This script helps test the Home Assistant Image Server endpoints

echo 🧪 Home Assistant Image Server Test Script
echo.

:: Set default server URL
set SERVER_URL=http://localhost:3000
if not "%1"=="" set SERVER_URL=%1

echo Server URL: %SERVER_URL%
echo.

:: Create test output directory
if not exist "test_images" mkdir test_images

echo 🔍 Basic Endpoint Tests
echo.

:: Test health endpoint
echo Testing: Health Check
echo GET %SERVER_URL%/health
curl -s "%SERVER_URL%/health"
if %errorlevel% equ 0 (
    echo ✅ SUCCESS: Health check passed
) else (
    echo ❌ FAILED: Health check failed
)
echo.
echo ---
echo.

:: Test cameras list endpoint
echo Testing: List Camera Entities
echo GET %SERVER_URL%/cameras
curl -s "%SERVER_URL%/cameras" | findstr "entity_id" >nul
if %errorlevel% equ 0 (
    echo ✅ SUCCESS: Cameras endpoint responded
) else (
    echo ❌ FAILED: Cameras endpoint failed
)
echo.
echo ---
echo.

echo 🖼️ Image Endpoint Tests
echo.
echo Note: The following tests may fail if you don't have these specific entities
echo.

:: Test common camera entities
call :test_image_endpoint "/image/entity/camera.front_door" "Front Door Camera" "test_images\front_door.jpg"
call :test_image_endpoint "/image/entity/camera.living_room" "Living Room Camera" "test_images\living_room.jpg"
call :test_image_endpoint "/image/entity/person.admin" "Admin Person Picture" "test_images\admin.jpg"
call :test_image_endpoint "/image/entity/weather.home" "Weather Icon" "test_images\weather.png"

:: Test URL-based image serving
call :test_image_endpoint "/image/url?url=/local/images/test.jpg" "URL-based Image Serving" "test_images\url_test.jpg"

:: Test non-existent entity (should return 404)
echo Testing error handling with non-existent entity
echo GET %SERVER_URL%/image/entity/camera.nonexistent
curl -s -w "%%{http_code}" "%SERVER_URL%/image/entity/camera.nonexistent" -o nul | findstr "404" >nul
if %errorlevel% equ 0 (
    echo ✅ SUCCESS: HTTP 404 for non-existent entity
) else (
    echo ❌ FAILED: Expected HTTP 404 for non-existent entity
)
echo.
echo ---
echo.

echo 🎯 Interactive Test Mode
echo.

:interactive_loop
echo Enter a custom entity ID to test (or 'quit' to exit):
set /p entity_id="> "

if /i "%entity_id%"=="quit" goto :end_interactive
if /i "%entity_id%"=="q" goto :end_interactive
if /i "%entity_id%"=="exit" goto :end_interactive

if not "%entity_id%"=="" (
    set filename=test_images\custom_%entity_id:.=_%.jpg
    call :test_image_endpoint "/image/entity/%entity_id%" "Custom Entity: %entity_id%" "!filename!"
)

goto :interactive_loop

:end_interactive

echo 🏁 Testing completed!
echo 📁 Test images saved in: test_images\
echo.

:: Show summary of saved images
if exist "test_images\*" (
    echo 📊 Successfully downloaded images:
    dir test_images /b
) else (
    echo ⚠️  No images were successfully downloaded
    echo This might be because:
    echo   - The server is not running
    echo   - Home Assistant is not accessible
    echo   - The test entities don't exist in your setup
    echo   - Authentication token is invalid
)

echo.
echo 💡 Tips:
echo   - Make sure your server is running: cargo run
echo   - Check your .env file has correct HA_URL and HA_TOKEN
echo   - Use /cameras endpoint to see available camera entities
echo   - Check Home Assistant Developer Tools ^> States for entity IDs
echo.
pause
goto :eof

:: Function to test image endpoint and save to file
:test_image_endpoint
set endpoint=%~1
set description=%~2
set filename=%~3

echo Testing: %description%
echo GET %SERVER_URL%%endpoint%

curl -s -w "%%{http_code}" -o "%filename%" "%SERVER_URL%%endpoint%" > temp_status.txt
set /p http_code=<temp_status.txt
del temp_status.txt

if "%http_code%"=="200" (
    if exist "%filename%" (
        for %%F in ("%filename%") do set file_size=%%~zF
        echo ✅ SUCCESS: HTTP %http_code% - Image saved (!file_size! bytes)
        echo 📁 Saved as: %filename%
    ) else (
        echo ❌ FAILED: HTTP %http_code% - Empty file
    )
) else (
    echo ❌ FAILED: HTTP %http_code%
    if exist "%filename%" (
        echo Error response:
        type "%filename%"
        del "%filename%"
    )
)
echo.
echo ---
echo.
goto :eof
