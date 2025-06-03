# Home Assistant TRMNL Entity Renderer

A high-performance Axum-based web server that renders Home Assistant entity status as images, optimized for TRMNL displays and dashboards.

🚀 **[Quick Deploy with Docker →](DEPLOYMENT.md)**

## ✨ Features

### 📟 TRMNL Display Support
- **800x480 1-bit grayscale** images optimized for e-ink displays
- **Visual gauges** for percentage sensors (battery, humidity, CPU, etc.)
- **Extra large text** for distance readability
- **Smart sensor detection** and formatting

### 🖼️ Multi-Sensor Dashboards
- **Combined status images** with multiple sensors
- **Professional layouts** with gradients and borders
- **Custom dimensions** and titles
- **Color-coded status indicators**

### 🏠 Home Assistant Integration
- **Entity status rendering** with readable bitmap fonts
- **Camera snapshot support** via Home Assistant API
- **Auto-discovery** of image URLs in entity attributes
- **CORS support** for web applications

### 🛠️ Developer Friendly
- **Fast async server** built with Axum
- **Cross-platform support** - Windows, Linux, macOS
- **Docker support** with multi-architecture builds
- **Comprehensive error handling** and logging

## 🚀 Quick Start

### 🐳 Docker (Recommended)

```bash
# Pull and run the latest image
docker run -d \
  --name ha-trmnl-renderer \
  -p 3000:3000 \
  -e HA_URL=http://your-homeassistant:8123 \
  -e HA_TOKEN=your_long_lived_access_token \
  --restart unless-stopped \
  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest

# Test TRMNL endpoint
curl "http://localhost:3000/trmnl?sensors=sensor.temperature,sensor.humidity_percent&title=TEST"
```

**📖 [Complete Docker deployment guide →](DEPLOYMENT.md)**

### 🧪 Testing Docker Build Locally

Before deploying, test the Docker build:

```bash
# Test Docker build (Linux/macOS)
./scripts/test-docker.sh

# Test Docker build (Windows)
.\scripts\test-docker.ps1
```

### 🦀 From Source

#### Prerequisites

- Rust 1.70+ installed
- Access to a Home Assistant instance
- A Home Assistant Long-Lived Access Token

### Environment Setup

Create a `.env` file in the project root:

```env
HA_URL=http://your-home-assistant:8123
HA_TOKEN=your_long_lived_access_token_here
PORT=3000
```

> 💡 **Cross-Platform**: The application automatically loads the `.env` file using the `dotenv` crate - no need to manually source environment variables on Windows, Linux, or macOS!

### Getting Your Home Assistant Token

1. Go to your Home Assistant web interface
2. Click on your profile (bottom left)
3. Scroll down to "Long-Lived Access Tokens"
4. Click "Create Token"
5. Give it a name like "Image Server"
6. Copy the token and use it as `HA_TOKEN`

### Running the Server

**Windows:**
```cmd
# Command Prompt
run.bat

# PowerShell (recommended)
.\run.ps1

# Or direct cargo run
cargo run
```

**Linux/macOS:**
```bash
# Using run script
chmod +x run.sh && ./run.sh

# Or direct cargo run
cargo run
```

The server will start on `http://localhost:3000` (or your specified PORT) and automatically load your `.env` file.

## API Endpoints

### Health Check
```
GET /health
```
Returns "OK" if the server is running.

### Serve Entity Image
```
GET /image/entity/{entity_id}
```
Serves an image for the specified Home Assistant entity.

**Examples:**
- `GET /image/entity/camera.front_door` - Camera snapshot
- `GET /image/entity/person.john` - Person's profile picture
- `GET /image/entity/weather.home` - Weather icon

**Query Parameters:**
- `width` (optional): Resize width
- `height` (optional): Resize height
- `cache` (optional): Enable/disable caching

### Serve Image by URL
```
GET /image/url?url={image_url}
```
Serves an image from a Home Assistant URL path.

**Example:**
```
GET /image/url?url=/local/images/floor_plan.png
```

### Render Entity Status as Static Image
```
GET /status/{entity_id}
```
Generates a static PNG image showing the entity's current status, state, and attributes.

**Examples:**
- `GET /status/sensor.temperature` - Temperature sensor status
- `GET /status/switch.living_room_lights` - Switch state visualization
- `GET /status/binary_sensor.front_door` - Door sensor status

**Query Parameters:**
- `width` (optional): Image width in pixels (default: 400)
- `height` (optional): Image height in pixels (default: 200)

**Example with custom size:**
```
GET /status/sensor.humidity?width=600&height=300
```

The generated image includes:
- Entity friendly name or ID as title
- Current state with units (if applicable)
- Visual status indicator (colored circle)
- Additional entity attributes (device class, battery, etc.)
- Color-coded background based on entity state

### Render Multiple Sensors in Combined Image
```
GET /multi-status?sensors={sensor1,sensor2,sensor3}
```
Generates a combined PNG image showing multiple sensors with their names and values.

**Examples:**
- `GET /multi-status?sensors=sensor.current_power_production,sensor.current_power_usage` - Power dashboard
- `GET /multi-status?sensors=sensor.living_room_temperature,sensor.bedroom_temperature&title=Temperature Dashboard` - Temperature overview

**Query Parameters:**
- `sensors` (required): Comma-separated list of sensor entity IDs (max 10)
- `width` (optional): Image width in pixels (default: 500)
- `height` (optional): Image height in pixels (auto-calculated based on sensor count)
- `title` (optional): Custom title for the dashboard (default: "Sensor Status")

**Example with all parameters:**
```
GET /multi-status?sensors=sensor.power_production,sensor.power_usage&title=Energy Dashboard&width=600&height=300
```

The generated image includes:
- Custom title header
- Each sensor with friendly name and formatted value
- Color-coded status indicators
- Professional layout with gradients and borders
- Proper number formatting with units

### Render TRMNL Display (800x480 1-bit)
```
GET /trmnl?sensors={sensor1,sensor2,sensor3}
```
Generates a 1-bit grayscale PNG image optimized for TRMNL displays at 800x480 pixels.

**Examples:**
- `GET /trmnl?sensors=sensor.current_power_production,sensor.current_power_usage&title=POWER STATUS` - Power display
- `GET /trmnl?sensors=sensor.temperature,sensor.humidity,sensor.pressure&title=ENVIRONMENT` - Environmental dashboard

**Query Parameters:**
- `sensors` (required): Comma-separated list of sensor entity IDs (max 15)
- `title` (optional): Custom title for the display (default: "SENSOR STATUS")

**TRMNL Features:**
- Fixed 800x480 pixel resolution
- 1-bit grayscale (black and white only)
- Optimized typography for e-ink displays
- High contrast design
- **Extra large titles and values** for distance readability
- **Visual gauges** for sensors with % unit of measurement
- Status indicators with patterns
- Clean layout suitable for grayscale displays

### List Camera Entities
```
GET /cameras
```
Returns a JSON list of all camera entities in your Home Assistant instance.

## Supported Entity Types

The server automatically detects images from various entity types:

- **Cameras**: Direct snapshot via `/api/camera_proxy/`
- **Persons**: Profile pictures from `entity_picture` attribute  
- **Weather**: Icons from `entity_picture` attribute
- **Media Players**: Album art from `entity_picture`
- **Status Images**: Generated PNG images for any entity showing current state
- **Custom entities**: Any entity with image attributes

## Image Attribute Detection

The server searches for images in these entity attributes (in order):
1. `entity_picture`
2. `image_url` 
3. `picture`
4. `thumbnail`
5. `media_content_id`

## Docker Support

### 🐳 Pre-built Docker Images

**GitHub Container Registry** (recommended):
```bash
# Pull latest image
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest

# Pull specific version
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:v1.0.0
```

**Multi-architecture support**: AMD64, ARM64 (Raspberry Pi, Apple Silicon)

### 🚀 Quick Start with Docker

**Using docker run:**
```bash
docker run -d \
  --name ha-trmnl-renderer \
  -p 3000:3000 \
  -e HA_URL=http://your-homeassistant:8123 \
  -e HA_TOKEN=your_long_lived_access_token \
  -e RUST_LOG=info \
  --restart unless-stopped \
  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
```

**Using Docker Compose:**
```yaml
version: '3.8'
services:
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
    container_name: ha-trmnl-renderer
    ports:
      - "3000:3000"
    environment:
      - HA_URL=http://homeassistant:8123
      - HA_TOKEN=your_long_lived_access_token_here
      - PORT=3000
      - RUST_LOG=info
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

**For Home Assistant Add-on style:**
```yaml
version: '3.8'
services:
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
    container_name: ha-trmnl-renderer
    network_mode: host
    environment:
      - HA_URL=http://localhost:8123
      - HA_TOKEN=your_long_lived_access_token_here
      - PORT=3000
    restart: unless-stopped
```

### 🔧 Building from Source

**Clone and build:**
```bash
git clone https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway.git
cd home-assistant-trmnl-entity-renderer-throwaway
docker build -t ha-trmnl-renderer .
```

**Multi-platform build:**
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t ha-trmnl-renderer .
```

### 📋 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HA_URL` | ✅ | - | Home Assistant URL (e.g., `http://homeassistant:8123`) |
| `HA_TOKEN` | ✅ | - | Home Assistant Long-Lived Access Token |
| `PORT` | ❌ | `3000` | Port to run the server on |
| `RUST_LOG` | ❌ | `info` | Log level (`error`, `warn`, `info`, `debug`, `trace`) |

### 🔍 Container Health Check

The container includes a built-in health check that verifies the `/health` endpoint:

```bash
# Check container health
docker ps
# Look for "healthy" status

# Manual health check
docker exec ha-trmnl-renderer curl -f http://localhost:3000/health
```

### 📊 Container Monitoring

**View logs:**
```bash
docker logs ha-trmnl-renderer
docker logs -f ha-trmnl-renderer  # Follow logs
```

**Container stats:**
```bash
docker stats ha-trmnl-renderer
```

### 🔄 Updates and Versioning

**Update to latest:**
```bash
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
docker stop ha-trmnl-renderer
docker rm ha-trmnl-renderer
# Run with new image (use same docker run command as above)
```

**Available tags:**
- `latest` - Latest stable release
- `main` - Latest development build  
- `v1.0.0` - Specific version tags
- `v1.0` - Minor version tags

### 🏠 Home Assistant Integration

**Add to Home Assistant's docker-compose.yml:**
```yaml
services:
  # ... your existing HA services
  
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
    container_name: ha-trmnl-renderer
    ports:
      - "3000:3000"
    environment:
      - HA_URL=http://homeassistant:8123
      - HA_TOKEN=${HA_TRMNL_TOKEN}  # Set in .env file
    restart: unless-stopped
    depends_on:
      - homeassistant
```

**Set environment in .env file:**
```env
HA_TRMNL_TOKEN=your_long_lived_access_token_here
```

### 📟 TRMNL-Specific Docker Usage

**TRMNL Power Dashboard:**
```bash
# Test your TRMNL endpoint
curl "http://localhost:3000/trmnl?sensors=sensor.current_power_production,sensor.current_power_usage,sensor.battery_percent&title=POWER%20STATUS"

# Save TRMNL image directly
curl "http://localhost:3000/trmnl?sensors=sensor.power_production,sensor.power_usage&title=ENERGY" -o trmnl_display.png
```

**TRMNL Automation in Home Assistant:**
```yaml
# automations.yaml
- alias: "Update TRMNL Display"
  trigger:
    - platform: time_pattern
      minutes: "/5"  # Every 5 minutes
  action:
    - service: shell_command.update_trmnl
      data:
        sensors: "sensor.power_production,sensor.power_usage,sensor.battery_percent"
        title: "POWER STATUS"

# configuration.yaml
shell_command:
  update_trmnl: >
    curl -s "http://ha-trmnl-renderer:3000/trmnl?sensors={{ sensors }}&title={{ title }}" 
    -o /config/www/trmnl_display.png
```

**Docker with volume for TRMNL images:**
```yaml
version: '3.8'
services:
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
    ports:
      - "3000:3000"
    environment:
      - HA_URL=http://homeassistant:8123
      - HA_TOKEN=your_token_here
    volumes:
      - ./trmnl_images:/app/images  # Save TRMNL images locally
    restart: unless-stopped
```

## Usage Examples

### HTML Integration
```html
<!DOCTYPE html>
<html>
<head>
    <title>Home Assistant Images</title>
</head>
<body>
    <h1>My Home</h1>
    
    <!-- Camera snapshot -->
    <img src="http://localhost:3000/image/entity/camera.front_door" 
         alt="Front Door Camera" width="640" height="480">
    
    <!-- Person picture -->
    <img src="http://localhost:3000/image/entity/person.john" 
         alt="John's Picture" width="100" height="100">
    
    <!-- Weather icon -->
    <img src="http://localhost:3000/image/entity/weather.home" 
         alt="Weather" width="64" height="64">
    
    <!-- Status images -->
    <img src="http://localhost:3000/status/sensor.temperature" 
         alt="Temperature Status" width="400" height="200">
    
    <img src="http://localhost:3000/status/switch.living_room_lights?width=300&height=150" 
         alt="Light Switch Status" width="300" height="150">
    
    <!-- Multi-sensor dashboard -->
    <img src="http://localhost:3000/multi-status?sensors=sensor.current_power_production,sensor.current_power_usage&title=Power Dashboard" 
         alt="Power Dashboard" width="500" height="160">
    
    <img src="http://localhost:3000/multi-status?sensors=sensor.living_room_temperature,sensor.bedroom_temperature,sensor.outdoor_temperature&title=Temperature Overview&width=600" 
         alt="Temperature Overview" width="600" height="200">
    
    <!-- TRMNL display -->
    <img src="http://localhost:3000/trmnl?sensors=sensor.current_power_production,sensor.current_power_usage&title=POWER STATUS" 
         alt="TRMNL Power Display" width="800" height="480" style="border: 2px solid #333;">
    
    <!-- TRMNL with percentage gauges -->
    <img src="http://localhost:3000/trmnl?sensors=sensor.battery_percent,sensor.cpu_percent,sensor.humidity_percent&title=SYSTEM STATUS" 
         alt="TRMNL System Gauges" width="800" height="480" style="border: 2px solid #333;">
</body>
</html>
```

### JavaScript Fetch
```javascript
// Get camera snapshot
fetch('http://localhost:3000/image/entity/camera.living_room')
  .then(response => response.blob())
  .then(blob => {
    const img = document.createElement('img');
    img.src = URL.createObjectURL(blob);
    document.body.appendChild(img);
  });

// List all cameras
fetch('http://localhost:3000/cameras')
  .then(response => response.json())
  .then(cameras => {
    cameras.forEach(camera => {
      console.log(`Camera: ${camera.entity_id} - ${camera.attributes.friendly_name}`);
    });
  });

// Get status image for a sensor
fetch('http://localhost:3000/status/sensor.temperature')
  .then(response => response.blob())
  .then(blob => {
    const img = document.createElement('img');
    img.src = URL.createObjectURL(blob);
    document.body.appendChild(img);
  });

// Get multi-sensor dashboard
const sensors = 'sensor.current_power_production,sensor.current_power_usage';
const title = 'Power Dashboard';
fetch(`http://localhost:3000/multi-status?sensors=${encodeURIComponent(sensors)}&title=${encodeURIComponent(title)}`)
  .then(response => response.blob())
  .then(blob => {
    const img = document.createElement('img');
    img.src = URL.createObjectURL(blob);
    document.body.appendChild(img);
  });

// Get TRMNL display with gauges
const trmnlSensors = 'sensor.battery_percent,sensor.cpu_percent,sensor.humidity_percent';
const trmnlTitle = 'SYSTEM STATUS';
fetch(`http://localhost:3000/trmnl?sensors=${encodeURIComponent(trmnlSensors)}&title=${encodeURIComponent(trmnlTitle)}`)
  .then(response => response.blob())
  .then(blob => {
    const img = document.createElement('img');
    img.src = URL.createObjectURL(blob);
    document.body.appendChild(img);
  });
```

### Home Assistant Automation
Use in Home Assistant notifications or dashboards:

```yaml
# In automations.yaml
- alias: "Send camera snapshot notification"
  trigger:
    - platform: state
      entity_id: binary_sensor.front_door
      to: 'on'
  action:
    - service: notify.mobile_app
      data:
        message: "Motion detected at front door"
        data:
          image: "http://your-server:3000/image/entity/camera.front_door"

# Status image in dashboard
- alias: "Update sensor status display"
  trigger:
    - platform: state
      entity_id: sensor.living_room_temperature
  action:
    - service: notify.persistent_notification
      data:
        title: "Temperature Update"
        message: "Current status image: http://your-server:3000/status/sensor.living_room_temperature"

# Multi-sensor dashboard in notification
- alias: "Daily energy report"
  trigger:
    - platform: time
      at: "18:00:00"
  action:
    - service: notify.mobile_app
      data:
        title: "Daily Energy Report"
        message: "Today's power summary"
        data:
          image: "http://your-server:3000/multi-status?sensors=sensor.daily_energy_production,sensor.daily_energy_usage&title=Daily Energy Summary"

# TRMNL integration
- alias: "Update TRMNL display"
  trigger:
    - platform: time_pattern
      minutes: "/5"  # Update every 5 minutes
  action:
    - service: shell_command.update_trmnl
      data:
        url: "http://your-server:3000/trmnl?sensors=sensor.power_production,sensor.power_usage,sensor.battery_percent&title=HOME STATUS"
```

## 🔧 Troubleshooting

### 📋 Quick Diagnostics

```bash
# Health check
curl http://localhost:3000/health

# Test TRMNL endpoint
curl "http://localhost:3000/trmnl?sensors=sensor.temperature&title=TEST" -o test.png

# Check logs (Docker)
docker logs ha-trmnl-renderer
```

### Common Issues

| Issue | Solution |
|-------|----------|
| **403 Forbidden** | Check your Home Assistant token permissions |
| **Connection refused** | Verify `HA_URL` is correct and accessible |
| **404 Not Found** | Entity doesn't exist or has no image |
| **Empty gauges** | Sensor must have `%` unit of measurement |
| **Timeout errors** | Check network connectivity to Home Assistant |

### Debug Mode
```bash
# Cargo
RUST_LOG=debug cargo run

# Docker
docker run ... -e RUST_LOG=debug ...
```

### Entity Debugging
1. Visit Home Assistant → Developer Tools → States
2. Find your entity and check its `unit_of_measurement`
3. For gauges, ensure unit is exactly `%`

### Platform-Specific
- **Windows**: Use `run.bat` or `run.ps1 -Debug -Port 8080`
- **Docker**: See [deployment guide](DEPLOYMENT.md) for detailed troubleshooting

## Performance Considerations

- Images are served with cache headers (`max-age=300`)
- Consider adding a reverse proxy (nginx) for production
- Camera snapshots are fetched in real-time
- No persistent caching implemented (images always fresh)

## Security Notes

- Server binds to `0.0.0.0` - consider firewall rules
- Home Assistant token has full API access
- No authentication on image endpoints
- CORS is permissive by default

### 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. **Test Docker build**: `./scripts/test-docker.sh` (or `.ps1` on Windows)
5. Test functionality with provided test scripts
6. Submit a pull request

### 🏷️ Creating Releases

```bash
# Test Docker build first
./scripts/test-docker.sh

# Create release
./scripts/release.sh

# Or manually tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### 🔧 Docker Build Notes

The Docker build has been optimized to handle missing `Cargo.lock` files automatically. If you encounter build issues:

1. **Run the test script**: `./scripts/test-docker.sh`
2. **Check Docker version**: Ensure Docker 20.10+ and BuildKit enabled
3. **Multi-platform builds**: Requires `docker buildx` for ARM64 support

## 📄 License

MIT License - feel free to use and modify as needed.

## 📋 Changelog

### v1.0.0
- **TRMNL display support** (800x480, 1-bit grayscale)
- **Visual gauges** for percentage sensors
- **Multi-sensor dashboards** with professional layouts
- **Large text optimization** for distance viewing
- **Docker support** with GitHub Container Registry
- **GitHub Actions** for automated builds and releases

### v0.1.0
- Initial release
- Basic entity image serving
- Camera snapshot support
- URL-based image serving
- Static entity status image generation
- Camera entity listing
- CORS support