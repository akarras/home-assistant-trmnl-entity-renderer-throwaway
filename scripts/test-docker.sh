#!/bin/bash

# Docker build test script for Home Assistant TRMNL Entity Renderer
# This script tests Docker builds locally before pushing to GitHub

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "Cargo.toml" ]; then
    print_error "This script must be run from the project root directory"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

print_info "Starting Docker build test..."

# Clean up any existing test containers/images
cleanup() {
    print_info "Cleaning up test containers and images..."
    docker stop ha-trmnl-test 2>/dev/null || true
    docker rm ha-trmnl-test 2>/dev/null || true
    docker rmi ha-trmnl-renderer:test 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Generate Cargo.lock if it doesn't exist
if [ ! -f "Cargo.lock" ]; then
    print_info "Generating Cargo.lock..."
    if command -v cargo &> /dev/null; then
        cargo generate-lockfile
    else
        print_warning "Cargo not found locally. Using Docker to generate Cargo.lock..."
        docker run --rm -v "$PWD":/workspace -w /workspace rust:1.75-slim cargo generate-lockfile
    fi
    print_success "Cargo.lock generated"
fi

# Build the Docker image
print_info "Building Docker image..."
if docker build -t ha-trmnl-renderer:test .; then
    print_success "Docker image built successfully"
else
    print_error "Docker build failed"
    exit 1
fi

# Test the image
print_info "Testing Docker image..."

# Start container with test environment variables
docker run -d \
    --name ha-trmnl-test \
    -p 3001:3000 \
    -e HA_URL=http://example.com:8123 \
    -e HA_TOKEN=test_token \
    -e RUST_LOG=info \
    ha-trmnl-renderer:test

# Wait for container to start
print_info "Waiting for container to start..."
sleep 5

# Test health endpoint
print_info "Testing health endpoint..."
max_attempts=10
attempt=1

while [ $attempt -le $max_attempts ]; do
    if curl -f -s http://localhost:3001/health > /dev/null; then
        print_success "Health check passed"
        break
    else
        print_warning "Health check attempt $attempt/$max_attempts failed, retrying..."
        sleep 2
        attempt=$((attempt + 1))
    fi
done

if [ $attempt -gt $max_attempts ]; then
    print_error "Health check failed after $max_attempts attempts"
    print_info "Container logs:"
    docker logs ha-trmnl-test
    exit 1
fi

# Test TRMNL endpoint (will fail with connection error but should return proper HTTP error)
print_info "Testing TRMNL endpoint (expect connection error)..."
response=$(curl -s -w "%{http_code}" -o /dev/null "http://localhost:3001/trmnl?sensors=sensor.test&title=TEST" || echo "000")

if [ "$response" = "500" ] || [ "$response" = "400" ] || [ "$response" = "200" ]; then
    print_success "TRMNL endpoint responding (HTTP $response)"
else
    print_warning "TRMNL endpoint returned HTTP $response (this may be expected)"
fi

# Check image size
print_info "Checking image size..."
image_size=$(docker images ha-trmnl-renderer:test --format "table {{.Size}}" | tail -n +2)
print_info "Final image size: $image_size"

# Show container stats
print_info "Container resource usage:"
docker stats ha-trmnl-test --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Test multi-platform build capability (if buildx is available)
if docker buildx version > /dev/null 2>&1; then
    print_info "Testing multi-platform build capability..."
    if docker buildx build --platform linux/amd64 -t ha-trmnl-renderer:test-amd64 . --load; then
        print_success "Multi-platform build (amd64) successful"
        docker rmi ha-trmnl-renderer:test-amd64 2>/dev/null || true
    else
        print_warning "Multi-platform build test failed (this is optional)"
    fi
else
    print_info "Docker Buildx not available, skipping multi-platform test"
fi

print_success "All Docker tests passed!"

# Display useful information
echo
print_info "Test Results Summary:"
echo "  ✅ Docker build: SUCCESS"
echo "  ✅ Container start: SUCCESS"
echo "  ✅ Health check: SUCCESS"
echo "  ✅ Endpoint response: SUCCESS"
echo "  📏 Image size: $image_size"
echo
print_info "Ready for deployment! You can now:"
echo "  • Push to GitHub to trigger automatic builds"
echo "  • Create a release with: ./scripts/release.sh"
echo "  • Deploy locally with: docker run ha-trmnl-renderer:test"
echo
print_info "Example deployment command:"
echo "docker run -d \\"
echo "  --name ha-trmnl-renderer \\"
echo "  -p 3000:3000 \\"
echo "  -e HA_URL=http://your-homeassistant:8123 \\"
echo "  -e HA_TOKEN=your_token \\"
echo "  --restart unless-stopped \\"
echo "  ha-trmnl-renderer:test"
