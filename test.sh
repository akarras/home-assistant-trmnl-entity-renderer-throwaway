#!/bin/bash

# Simple Image Server Test Script
# This script helps test the Home Assistant Image Server endpoints

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default server URL
SERVER_URL=${SERVER_URL:-"http://localhost:3000"}

echo -e "${BLUE}🧪 Home Assistant Image Server Test Script${NC}"
echo -e "${BLUE}Server URL: $SERVER_URL${NC}"
echo

# Function to test an endpoint
test_endpoint() {
    local endpoint=$1
    local description=$2
    local expected_status=${3:-200}

    echo -e "${YELLOW}Testing: $description${NC}"
    echo -e "${BLUE}GET $SERVER_URL$endpoint${NC}"

    response=$(curl -s -w "\n%{http_code}" "$SERVER_URL$endpoint")
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n -1)

    if [ "$status_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✅ SUCCESS: HTTP $status_code${NC}"
    else
        echo -e "${RED}❌ FAILED: Expected HTTP $expected_status, got HTTP $status_code${NC}"
    fi

    echo "Response body:"
    echo "$body" | head -10
    echo
    echo "---"
    echo
}

# Function to test image endpoint and save to file
test_image_endpoint() {
    local endpoint=$1
    local description=$2
    local filename=$3

    echo -e "${YELLOW}Testing: $description${NC}"
    echo -e "${BLUE}GET $SERVER_URL$endpoint${NC}"

    http_code=$(curl -s -w "%{http_code}" -o "$filename" "$SERVER_URL$endpoint")

    if [ "$http_code" -eq "200" ]; then
        if [ -f "$filename" ] && [ -s "$filename" ]; then
            file_size=$(stat -f%z "$filename" 2>/dev/null || stat -c%s "$filename" 2>/dev/null)
            echo -e "${GREEN}✅ SUCCESS: HTTP $http_code - Image saved ($file_size bytes)${NC}"
            echo -e "${GREEN}📁 Saved as: $filename${NC}"
        else
            echo -e "${RED}❌ FAILED: HTTP $http_code - Empty file${NC}"
        fi
    else
        echo -e "${RED}❌ FAILED: HTTP $http_code${NC}"
        if [ -f "$filename" ]; then
            echo "Error response:"
            cat "$filename"
            rm "$filename"
        fi
    fi
    echo
    echo "---"
    echo
}

# Create test output directory
mkdir -p test_images

echo -e "${BLUE}🔍 Basic Endpoint Tests${NC}"
echo

# Test health endpoint
test_endpoint "/health" "Health Check"

# Test cameras list endpoint
test_endpoint "/cameras" "List Camera Entities"

echo -e "${BLUE}🖼️ Image Endpoint Tests${NC}"
echo

# Test some common camera entities (these might not exist in your setup)
echo -e "${YELLOW}Note: The following tests may fail if you don't have these specific entities${NC}"
echo

test_image_endpoint "/image/entity/camera.front_door" "Front Door Camera" "test_images/front_door.jpg"
test_image_endpoint "/image/entity/camera.living_room" "Living Room Camera" "test_images/living_room.jpg"
test_image_endpoint "/image/entity/person.admin" "Admin Person Picture" "test_images/admin.jpg"
test_image_endpoint "/image/entity/weather.home" "Weather Icon" "test_images/weather.png"

# Test URL-based image serving
test_image_endpoint "/image/url?url=/local/images/test.jpg" "URL-based Image Serving" "test_images/url_test.jpg"

# Test non-existent entity (should return 404)
echo -e "${YELLOW}Testing error handling with non-existent entity${NC}"
test_endpoint "/image/entity/camera.nonexistent" "Non-existent Camera Entity" 404

echo -e "${BLUE}🎯 Interactive Test Mode${NC}"
echo

# Interactive mode for custom testing
while true; do
    echo -e "${YELLOW}Enter a custom entity ID to test (or 'quit' to exit):${NC}"
    read -r entity_id

    if [ "$entity_id" = "quit" ] || [ "$entity_id" = "q" ] || [ "$entity_id" = "exit" ]; then
        break
    fi

    if [ -n "$entity_id" ]; then
        filename="test_images/custom_$(echo "$entity_id" | tr '.' '_').jpg"
        test_image_endpoint "/image/entity/$entity_id" "Custom Entity: $entity_id" "$filename"
    fi
done

echo -e "${GREEN}🏁 Testing completed!${NC}"
echo -e "${BLUE}Test images saved in: test_images/${NC}"

# Show summary of saved images
if [ -d "test_images" ] && [ "$(ls -A test_images)" ]; then
    echo -e "${GREEN}📊 Successfully downloaded images:${NC}"
    ls -lh test_images/
else
    echo -e "${YELLOW}⚠️  No images were successfully downloaded${NC}"
    echo -e "${YELLOW}This might be because:${NC}"
    echo -e "${YELLOW}  - The server is not running${NC}"
    echo -e "${YELLOW}  - Home Assistant is not accessible${NC}"
    echo -e "${YELLOW}  - The test entities don't exist in your setup${NC}"
    echo -e "${YELLOW}  - Authentication token is invalid${NC}"
fi

echo
echo -e "${BLUE}💡 Tips:${NC}"
echo -e "${BLUE}  - Make sure your server is running: cargo run${NC}"
echo -e "${BLUE}  - Check your .env file has correct HA_URL and HA_TOKEN${NC}"
echo -e "${BLUE}  - Use /cameras endpoint to see available camera entities${NC}"
echo -e "${BLUE}  - Check Home Assistant Developer Tools > States for entity IDs${NC}"
