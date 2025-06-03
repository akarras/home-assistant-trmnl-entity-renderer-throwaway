@echo off
REM Test script for the multi-sensor status endpoint
REM This script tests the new /multi-status endpoint with various sensor combinations

set SERVER_URL=http://localhost:3000

echo 🧪 Testing Multi-Sensor Status Endpoint
echo =======================================

REM Check if server is running
echo 1. Testing server health...
curl -s "%SERVER_URL%/health" >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ Server is running
) else (
    echo ❌ Server is not running. Please start the server first.
    pause
    exit /b 1
)

REM Create test directory
if not exist "test_output\multi_sensor" mkdir "test_output\multi_sensor"

echo.
echo 2. Testing multi-sensor combinations...

REM Test 1: Power sensors
echo Testing power sensors:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.current_power_production,sensor.current_power_usage&title=Power%%20Dashboard" -o "test_output\multi_sensor\power_dashboard.png" -w "  Power Dashboard: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test 2: Temperature sensors
echo Testing temperature sensors:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.living_room_temperature,sensor.bedroom_temperature,sensor.outdoor_temperature&title=Temperature%%20Overview" -o "test_output\multi_sensor\temperature_overview.png" -w "  Temperature Overview: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test 3: Mixed sensor types
echo Testing mixed sensor types:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.temperature,sensor.humidity,sensor.battery&title=Home%%20Sensors" -o "test_output\multi_sensor\home_sensors.png" -w "  Home Sensors: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test 4: Single sensor (edge case)
echo Testing single sensor:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.temperature&title=Single%%20Sensor" -o "test_output\multi_sensor\single_sensor.png" -w "  Single Sensor: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test 5: Custom dimensions
echo Testing custom dimensions:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.power,sensor.voltage&title=Electrical&width=600&height=300" -o "test_output\multi_sensor\electrical_custom.png" -w "  Custom Size: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test 6: Many sensors (stress test)
echo Testing many sensors:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.temp1,sensor.temp2,sensor.temp3,sensor.temp4,sensor.temp5&title=Multi%%20Temperature" -o "test_output\multi_sensor\many_sensors.png" -w "  Many Sensors: HTTP %%{http_code} - %%{size_download} bytes\n"

echo.
echo 3. Testing edge cases...

REM Test empty sensors parameter
echo Testing empty sensors parameter:
curl -s "%SERVER_URL%/multi-status?sensors=" -w "  Empty sensors: HTTP %%{http_code} - %%{size_download} bytes\n" >nul

REM Test missing sensors parameter
echo Testing missing sensors parameter:
curl -s "%SERVER_URL%/multi-status" -w "  Missing sensors: HTTP %%{http_code} - %%{size_download} bytes\n" >nul

REM Test too many sensors (>10)
echo Testing too many sensors:
curl -s "%SERVER_URL%/multi-status?sensors=s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11" -w "  Too many sensors: HTTP %%{http_code} - %%{size_download} bytes\n" >nul

REM Test non-existent sensors
echo Testing non-existent sensors:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.non_existent1,sensor.non_existent2&title=Non%%20Existent" -o "test_output\multi_sensor\non_existent.png" -w "  Non-existent sensors: HTTP %%{http_code} - %%{size_download} bytes\n"

echo.
echo 4. Testing various titles and formatting...

REM Test with special characters in title
echo Testing special characters in title:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.temp&title=Test%%20%%26%%20Demo%%20-%%20Temperature" -o "test_output\multi_sensor\special_chars.png" -w "  Special chars: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test with no title (default)
echo Testing default title:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.humidity,sensor.pressure" -o "test_output\multi_sensor\default_title.png" -w "  Default title: HTTP %%{http_code} - %%{size_download} bytes\n"

REM Test with very long title
echo Testing long title:
curl -s "%SERVER_URL%/multi-status?sensors=sensor.temp&title=This%%20is%%20a%%20very%%20long%%20title%%20that%%20should%%20be%%20handled%%20properly" -o "test_output\multi_sensor\long_title.png" -w "  Long title: HTTP %%{http_code} - %%{size_download} bytes\n"

echo.
echo 5. Performance test...
echo Generating 5 multi-sensor images to test performance:

set start_time=%time%
for /L %%i in (1,1,5) do (
    curl -s "%SERVER_URL%/multi-status?sensors=sensor.temp,sensor.humidity&title=Performance%%20Test%%20%%i" >nul
    echo|set /p="."
)
set end_time=%time%

echo.
echo Performance test completed
echo Note: Precise timing requires PowerShell or additional tools

echo.
echo ✅ Multi-sensor testing complete!
echo 📁 Generated images saved to: test_output\multi_sensor\
echo.
echo To view the generated images:
echo   explorer test_output\multi_sensor
echo.
echo Example URLs to test in browser:
echo   %SERVER_URL%/multi-status?sensors=sensor.current_power_production,sensor.current_power_usage^&title=Power%%20Dashboard
echo   %SERVER_URL%/multi-status?sensors=sensor.living_room_temperature,sensor.bedroom_temperature^&title=Temperature%%20Status
echo   %SERVER_URL%/multi-status?sensors=sensor.humidity,sensor.pressure^&width=600^&height=250
echo.
echo 💡 Tips:
echo   - Use comma-separated sensor names without spaces
echo   - URL-encode titles with spaces (%%20 for space)
echo   - Maximum 10 sensors per request
echo   - Height auto-adjusts based on sensor count if not specified
echo.
pause
