#!/bin/bash

# Test script for the TRMNL endpoint
# This script tests the new /trmnl endpoint optimized for TRMNL displays (800x480, 1-bit)

SERVER_URL="http://localhost:3000"

echo "📟 Testing TRMNL Display Endpoint"
echo "================================="
echo "Target: 800x480 pixels, 1-bit grayscale PNG"

# Check if server is running
echo "1. Testing server health..."
if curl -s "$SERVER_URL/health" > /dev/null; then
    echo "✅ Server is running"
else
    echo "❌ Server is not running. Please start the server first."
    exit 1
fi

# Create test directory
mkdir -p test_output/trmnl

echo ""
echo "2. Testing TRMNL sensor combinations..."

# Test 1: Power dashboard (typical TRMNL use case)
echo "Testing power dashboard:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.current_power_production,sensor.current_power_usage&title=POWER%20STATUS" \
    -o "test_output/trmnl/power_status.png" \
    -w "  Power Status: HTTP %{http_code} - %{size_download} bytes\n"

# Test 2: Environmental sensors with percentage gauges
echo "Testing environmental dashboard:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.temperature,sensor.humidity_percent,sensor.battery_percent&title=ENVIRONMENT" \
    -o "test_output/trmnl/environment.png" \
    -w "  Environment: HTTP %{http_code} - %{size_download} bytes\n"

# Test 3: Energy monitoring
echo "Testing energy monitoring:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.solar_power,sensor.grid_power,sensor.battery_power,sensor.house_consumption&title=ENERGY%20MONITOR" \
    -o "test_output/trmnl/energy_monitor.png" \
    -w "  Energy Monitor: HTTP %{http_code} - %{size_download} bytes\n"

# Test 4: Home overview with percentage sensors
echo "Testing home overview:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.living_room_temperature,sensor.humidity_percent,sensor.battery_percent,sensor.disk_usage_percent&title=HOME%20STATUS" \
    -o "test_output/trmnl/home_status.png" \
    -w "  Home Status: HTTP %{http_code} - %{size_download} bytes\n"

# Test 5: Weather station
echo "Testing weather station:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.outdoor_temperature,sensor.outdoor_humidity,sensor.wind_speed,sensor.rainfall,sensor.barometric_pressure&title=WEATHER%20STATION" \
    -o "test_output/trmnl/weather_station.png" \
    -w "  Weather Station: HTTP %{http_code} - %{size_download} bytes\n"

# Test 6: Maximum sensors (15) with mix of values and percentages
echo "Testing maximum sensors (15):"
curl -s "$SERVER_URL/trmnl?sensors=sensor.temp1,sensor.temp2,sensor.humidity_percent,sensor.battery_percent,sensor.cpu_percent,sensor.memory_percent,sensor.disk_percent,sensor.pressure1,sensor.light1,sensor.motion1,sensor.door1,sensor.window1,sensor.wifi_percent,sensor.load_percent,sensor.uptime&title=FULL%20DASHBOARD" \
    -o "test_output/trmnl/full_dashboard.png" \
    -w "  Full Dashboard (15 sensors): HTTP %{http_code} - %{size_download} bytes\n"

# Test 7: Single sensor (minimal)
echo "Testing single sensor:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.temperature&title=TEMPERATURE" \
    -o "test_output/trmnl/single_temp.png" \
    -w "  Single Temperature: HTTP %{http_code} - %{size_download} bytes\n"

# Test 8: Default title
echo "Testing default title:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.power_production,sensor.power_usage" \
    -o "test_output/trmnl/default_title.png" \
    -w "  Default Title: HTTP %{http_code} - %{size_download} bytes\n"

echo ""
echo "3. Testing TRMNL edge cases..."

# Test empty sensors parameter
echo "Testing empty sensors parameter:"
curl -s "$SERVER_URL/trmnl?sensors=" \
    -w "  Empty sensors: HTTP %{http_code} - %{size_download} bytes\n" \
    > /dev/null

# Test missing sensors parameter
echo "Testing missing sensors parameter:"
curl -s "$SERVER_URL/trmnl" \
    -w "  Missing sensors: HTTP %{http_code} - %{size_download} bytes\n" \
    > /dev/null

# Test too many sensors (>15)
echo "Testing too many sensors (>15):"
curl -s "$SERVER_URL/trmnl?sensors=s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14,s15,s16" \
    -w "  Too many sensors: HTTP %{http_code} - %{size_download} bytes\n" \
    > /dev/null

# Test non-existent sensors
echo "Testing non-existent sensors:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.non_existent1,sensor.non_existent2&title=UNAVAILABLE" \
    -o "test_output/trmnl/unavailable_sensors.png" \
    -w "  Unavailable sensors: HTTP %{http_code} - %{size_download} bytes\n"

echo ""
echo "4. Testing percentage sensor gauges..."

# Test percentage sensors specifically
echo "Testing battery and system metrics:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.battery_percent,sensor.cpu_percent,sensor.memory_percent,sensor.disk_percent&title=SYSTEM%20STATUS" \
    -o "test_output/trmnl/system_gauges.png" \
    -w "  System Gauges: HTTP %{http_code} - %{size_download} bytes\n"

# Test humidity and environmental percentages
echo "Testing environmental percentages:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.humidity_percent,sensor.air_quality_percent,sensor.uv_index_percent&title=AIR%20QUALITY" \
    -o "test_output/trmnl/air_quality.png" \
    -w "  Air Quality: HTTP %{http_code} - %{size_download} bytes\n"

echo ""
echo "5. Testing TRMNL title variations..."

# Test long title
echo "Testing long title:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.temp&title=THIS%20IS%20A%20VERY%20LONG%20TITLE%20FOR%20TRMNL%20DISPLAY" \
    -o "test_output/trmnl/long_title.png" \
    -w "  Long title: HTTP %{http_code} - %{size_download} bytes\n"

# Test special characters in title
echo "Testing special characters:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.temp&title=POWER%20%26%20ENERGY%20-%20STATUS" \
    -o "test_output/trmnl/special_chars.png" \
    -w "  Special chars: HTTP %{http_code} - %{size_download} bytes\n"

# Test uppercase title (TRMNL convention)
echo "Testing uppercase title:"
curl -s "$SERVER_URL/trmnl?sensors=sensor.temp,sensor.humidity&title=SMART%20HOME%20DASHBOARD" \
    -o "test_output/trmnl/uppercase_title.png" \
    -w "  Uppercase title: HTTP %{http_code} - %{size_download} bytes\n"

echo ""
echo "6. TRMNL Performance test..."
echo "Generating 5 TRMNL images to test performance:"

start_time=$(date +%s.%N)
for i in {1..5}; do
    curl -s "$SERVER_URL/trmnl?sensors=sensor.temp,sensor.humidity&title=PERF%20TEST%20$i" > /dev/null
    echo -n "."
done
end_time=$(date +%s.%N)

duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
if [ "$duration" != "N/A" ]; then
    avg_time=$(echo "scale=3; $duration / 5" | bc 2>/dev/null || echo "N/A")
    echo ""
    echo "Total time: ${duration}s"
    echo "Average time per TRMNL image: ${avg_time}s"
else
    echo ""
    echo "Performance measurement not available (bc not installed)"
fi

echo ""
echo "7. Image format verification..."
echo "Checking generated images with file command:"

for img in test_output/trmnl/*.png; do
    if [ -f "$img" ]; then
        filename=$(basename "$img")
        file_info=$(file "$img" 2>/dev/null || echo "file command not available")
        echo "  $filename: $file_info"
    fi
done

echo ""
echo "✅ TRMNL testing complete!"
echo "📁 Generated TRMNL images saved to: test_output/trmnl/"
echo ""
echo "📟 TRMNL Display Information:"
echo "  - Resolution: 800x480 pixels"
echo "  - Format: 1-bit grayscale PNG"
echo "  - Optimized for e-ink displays"
echo "  - High contrast black and white"
echo ""
echo "To view the generated images:"
echo "  - On Windows: explorer test_output\\trmnl"
echo "  - On macOS: open test_output/trmnl"
echo "  - On Linux: xdg-open test_output/trmnl"
echo ""
echo "Example TRMNL URLs:"
echo "  $SERVER_URL/trmnl?sensors=sensor.current_power_production,sensor.current_power_usage&title=POWER%20STATUS"
echo "  $SERVER_URL/trmnl?sensors=sensor.temperature,sensor.humidity_percent,sensor.battery_percent&title=ENVIRONMENT"
echo "  $SERVER_URL/trmnl?sensors=sensor.battery_percent,sensor.cpu_percent,sensor.memory_percent&title=SYSTEM%20STATUS"
echo ""
echo "💡 TRMNL Tips:"
echo "  - Use UPPERCASE titles for better TRMNL aesthetics"
echo "  - Maximum 15 sensors per display"
echo "  - Sensor names are automatically truncated if too long"
echo "  - Sensors with % unit display as visual gauges"
echo "  - Large values for better readability at distance"
echo "  - Images are optimized for grayscale e-ink displays"
echo "  - Perfect for IoT dashboards and status displays"
