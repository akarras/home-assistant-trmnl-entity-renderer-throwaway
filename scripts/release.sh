#!/bin/bash

# Release script for Home Assistant TRMNL Entity Renderer
# This script helps create version tags that trigger GitHub Actions

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

# Check if git is clean
if [ -n "$(git status --porcelain)" ]; then
    print_error "Git working directory is not clean. Please commit or stash your changes."
    git status --short
    exit 1
fi

# Check if we're on main/master branch
current_branch=$(git branch --show-current)
if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
    print_warning "You are not on the main/master branch (current: $current_branch)"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Release cancelled."
        exit 0
    fi
fi

# Get current version from Cargo.toml
current_version=$(grep '^version' Cargo.toml | sed 's/version = "\(.*\)"/\1/')
print_info "Current version: $current_version"

# Prompt for new version
echo
echo "Release types:"
echo "  1) Patch release (e.g., 1.0.0 -> 1.0.1)"
echo "  2) Minor release (e.g., 1.0.1 -> 1.1.0)"
echo "  3) Major release (e.g., 1.1.0 -> 2.0.0)"
echo "  4) Custom version"
echo

read -p "Select release type (1-4): " release_type

case $release_type in
    1)
        # Patch release
        IFS='.' read -ra VERSION_PARTS <<< "$current_version"
        major=${VERSION_PARTS[0]}
        minor=${VERSION_PARTS[1]}
        patch=$((${VERSION_PARTS[2]} + 1))
        new_version="$major.$minor.$patch"
        ;;
    2)
        # Minor release
        IFS='.' read -ra VERSION_PARTS <<< "$current_version"
        major=${VERSION_PARTS[0]}
        minor=$((${VERSION_PARTS[1]} + 1))
        new_version="$major.$minor.0"
        ;;
    3)
        # Major release
        IFS='.' read -ra VERSION_PARTS <<< "$current_version"
        major=$((${VERSION_PARTS[0]} + 1))
        new_version="$major.0.0"
        ;;
    4)
        # Custom version
        read -p "Enter new version (e.g., 1.2.3): " new_version
        if [[ ! $new_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "Invalid version format. Please use semantic versioning (e.g., 1.2.3)"
            exit 1
        fi
        ;;
    *)
        print_error "Invalid selection"
        exit 1
        ;;
esac

print_info "New version will be: $new_version"

# Confirm release
echo
read -p "Create release v$new_version? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Release cancelled."
    exit 0
fi

# Update version in Cargo.toml
print_info "Updating Cargo.toml version..."
sed -i.bak "s/^version = \".*\"/version = \"$new_version\"/" Cargo.toml
rm Cargo.toml.bak

# Update Cargo.lock
print_info "Updating Cargo.lock..."
cargo check > /dev/null 2>&1

# Commit version bump
print_info "Committing version bump..."
git add Cargo.toml Cargo.lock
git commit -m "chore: bump version to v$new_version"

# Create and push tag
print_info "Creating git tag v$new_version..."
git tag -a "v$new_version" -m "Release version $new_version

Features:
- TRMNL display support (800x480, 1-bit grayscale)
- Multi-sensor status images with visual gauges
- Large text optimized for distance viewing
- Docker support with multi-architecture builds

Docker:
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:v$new_version"

# Push changes and tag
print_info "Pushing changes and tag to remote..."
git push origin $current_branch
git push origin "v$new_version"

print_success "Release v$new_version created successfully!"
echo
print_info "GitHub Actions will now:"
print_info "  • Build Docker images for multiple architectures"
print_info "  • Create GitHub release with binaries"
print_info "  • Publish to GitHub Container Registry"
echo
print_info "Monitor the release at:"
print_info "  https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway/releases"
print_info "  https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway/actions"
echo
print_info "Docker image will be available at:"
print_info "  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:v$new_version"
print_info "  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest"
