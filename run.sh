#!/bin/bash

# Home Assistant Image Server Startup Script
# This script helps you start the server with proper environment setup

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Home Assistant Image Server Startup Script${NC}"
echo

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️  No .env file found. Creating one from template...${NC}"

    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "${GREEN}✅ Created .env from .env.example${NC}"
        echo -e "${YELLOW}📝 Please edit .env file with your Home Assistant details:${NC}"
        echo -e "${YELLOW}   - HA_URL: Your Home Assistant URL${NC}"
        echo -e "${YELLOW}   - HA_TOKEN: Your Long-Lived Access Token${NC}"
        echo
        echo -e "${YELLOW}Press Enter to continue after editing .env, or Ctrl+C to exit...${NC}"
        read -r
    else
        echo -e "${RED}❌ No .env.example file found!${NC}"
        echo -e "${YELLOW}Creating basic .env file...${NC}"
        cat > .env << 'EOF'
# Home Assistant Configuration
HA_URL=http://localhost:8123
HA_TOKEN=your_long_lived_access_token_here

# Server Configuration
PORT=3000

# Logging Level
RUST_LOG=info
EOF
        echo -e "${GREEN}✅ Basic .env file created${NC}"
        echo -e "${YELLOW}📝 Please edit .env file with your Home Assistant details${NC}"
        exit 1
    fi
fi

# Load environment variables
if [ -f ".env" ]; then
    echo -e "${BLUE}📋 Loading environment variables from .env...${NC}"
    export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)
fi

# Validate required environment variables
if [ -z "$HA_URL" ] || [ "$HA_URL" = "your_home_assistant_url_here" ]; then
    echo -e "${RED}❌ HA_URL not set in .env file${NC}"
    exit 1
fi

if [ -z "$HA_TOKEN" ] || [ "$HA_TOKEN" = "your_long_lived_access_token_here" ]; then
    echo -e "${RED}❌ HA_TOKEN not set in .env file${NC}"
    echo -e "${YELLOW}To get your token:${NC}"
    echo -e "${YELLOW}1. Go to Home Assistant > Profile > Long-Lived Access Tokens${NC}"
    echo -e "${YELLOW}2. Create Token > Copy the token${NC}"
    echo -e "${YELLOW}3. Update HA_TOKEN in .env file${NC}"
    exit 1
fi

# Set default values
export PORT=${PORT:-3000}
export RUST_LOG=${RUST_LOG:-info}

echo -e "${GREEN}✅ Environment configured:${NC}"
echo -e "${BLUE}   HA_URL: $HA_URL${NC}"
echo -e "${BLUE}   HA_TOKEN: ${HA_TOKEN:0:10}...${NC}"
echo -e "${BLUE}   PORT: $PORT${NC}"
echo -e "${BLUE}   RUST_LOG: $RUST_LOG${NC}"
echo

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}❌ Cargo (Rust) not found!${NC}"
    echo -e "${YELLOW}Please install Rust from: https://rustup.rs/${NC}"
    exit 1
fi

# Check if we can reach Home Assistant
echo -e "${BLUE}🔍 Testing Home Assistant connection...${NC}"
if command -v curl &> /dev/null; then
    if curl -s -f -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/" > /dev/null; then
        echo -e "${GREEN}✅ Home Assistant is reachable${NC}"
    else
        echo -e "${YELLOW}⚠️  Warning: Could not reach Home Assistant at $HA_URL${NC}"
        echo -e "${YELLOW}   Server will still start, but image serving may not work${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  curl not found, skipping Home Assistant connectivity test${NC}"
fi

echo

# Function to handle cleanup on exit
cleanup() {
    echo
    echo -e "${YELLOW}🛑 Shutting down server...${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Build and run the server
echo -e "${BLUE}🔨 Building and starting the server...${NC}"
echo -e "${BLUE}📍 Server will be available at: http://localhost:$PORT${NC}"
echo -e "${BLUE}🧪 Test page available at: file://$(pwd)/test.html${NC}"
echo
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo

# Start the server
cargo run

# This should not be reached due to trap, but just in case
cleanup
