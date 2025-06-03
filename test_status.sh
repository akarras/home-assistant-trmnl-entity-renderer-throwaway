#!/bin/bash

# Test script for the status image endpoint
# This script tests various entity types with the new /status endpoint

SERVER_URL="http://localhost:3000"

echo "🧪 Testing Status Image Endpoint"
echo "================================"

# Check if server is running
echo "1. Testing server health..."
if curl -s "$SERVER_URL/health" > /dev/null; then
    echo "✅ Server is running"
else
    echo "❌ Server is not running. Please start the server first."
    exit 1
fi

# Create test directory
mkdir -p test_output

echo ""
echo "2. Testing various entity status images..."

# Test different entity types
declare -a test_entities=(
    "sensor.temperature"
    "switch.living_room_lights"
    "binary_sensor.front_door"
    "light.bedroom_light"
    "device_tracker.phone"
    "person.admin"
    "weather.home"
    "climate.thermostat"
)

for entity in "${test_entities[@]}"; do
    echo "Testing entity: $entity"

    # Test default size
    curl -s "$SERVER_URL/status/$entity" \
        -o "test_output/${entity//\./_}_default.png" \
        -w "  Default (400x200): HTTP %{http_code} - %{size_download} bytes\n"

    # Test custom size
    curl -s "$SERVER_URL/status/$entity?width=600&height=300" \
        -o "test_output/${entity//\./_}_large.png" \
        -w "  Large (600x300): HTTP %{http_code} - %{size_download} bytes\n"

    # Test small size
    curl -s "$SERVER_URL/status/$entity?width=200&height=100" \
        -o "test_output/${entity//\./_}_small.png" \
        -w "  Small (200x100): HTTP %{http_code} - %{size_download} bytes\n"

    echo ""
done

echo "3. Testing edge cases..."

# Test non-existent entity
echo "Testing non-existent entity:"
curl -s "$SERVER_URL/status/sensor.non_existent" \
    -w "  HTTP %{http_code} - %{size_download} bytes\n" \
    > /dev/null

# Test invalid dimensions
echo "Testing invalid dimensions:"
curl -s "$SERVER_URL/status/sensor.temperature?width=0&height=0" \
    -w "  HTTP %{http_code} - %{size_download} bytes\n" \
    > /dev/null

# Test very large dimensions
echo "Testing large dimensions:"
curl -s "$SERVER_URL/status/sensor.temperature?width=2000&height=1000" \
    -w "  HTTP %{http_code} - %{size_download} bytes\n" \
    > /dev/null

echo ""
echo "4. Performance test..."
echo "Generating 10 status images to test performance:"

start_time=$(date +%s.%N)
for i in {1..10}; do
    curl -s "$SERVER_URL/status/sensor.temperature" > /dev/null
    echo -n "."
done
end_time=$(date +%s.%N)

duration=$(echo "$end_time - $start_time" | bc)
avg_time=$(echo "scale=3; $duration / 10" | bc)

echo ""
echo "Total time: ${duration}s"
echo "Average time per image: ${avg_time}s"

echo ""
echo "✅ Testing complete!"
echo "📁 Generated images saved to: test_output/"
echo ""
echo "To view the generated images:"
echo "  - On Windows: explorer test_output"
echo "  - On macOS: open test_output"
echo "  - On Linux: xdg-open test_output"
echo ""
echo "Example URLs to test in browser:"
echo "  $SERVER_URL/status/sensor.temperature"
echo "  $SERVER_URL/status/switch.living_room_lights?width=500&height=250"
echo "  $SERVER_URL/status/binary_sensor.front_door"
