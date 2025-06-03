# Deployment Guide

This guide covers deploying the Home Assistant TRMNL Entity Renderer using Docker and GitHub Container Registry.

## 🚀 Quick Start

### Pull and Run Pre-built Docker Image

```bash
# Pull the latest image
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest

# Run with environment variables
docker run -d \
  --name ha-trmnl-renderer \
  -p 3000:3000 \
  -e HA_URL=http://your-homeassistant:8123 \
  -e HA_TOKEN=your_long_lived_access_token \
  --restart unless-stopped \
  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
```

### Test the Deployment

```bash
# Health check
curl http://localhost:3000/health

# Test TRMNL endpoint
curl "http://localhost:3000/trmnl?sensors=sensor.temperature,sensor.humidity&title=TEST" -o test.png
```

## 🐳 Docker Deployment Options

### 1. Docker Run (Simple)

```bash
docker run -d \
  --name ha-trmnl-renderer \
  -p 3000:3000 \
  -e HA_URL=http://homeassistant.local:8123 \
  -e HA_TOKEN=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9... \
  -e RUST_LOG=info \
  --restart unless-stopped \
  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
```

### 2. Docker Compose (Recommended)

Create `docker-compose.yml`:

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
      - HA_TOKEN=${HA_TOKEN}  # Set in .env file
      - RUST_LOG=info
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

Create `.env` file:

```env
HA_TOKEN=your_long_lived_access_token_here
```

Deploy:

```bash
docker-compose up -d
```

### 3. Home Assistant Integration

Add to your existing Home Assistant `docker-compose.yml`:

```yaml
version: '3.8'
services:
  homeassistant:
    # ... your existing HA config
    
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
    container_name: ha-trmnl-renderer
    network_mode: host  # Simplifies networking with HA
    environment:
      - HA_URL=http://localhost:8123
      - HA_TOKEN=${HA_TRMNL_TOKEN}
      - PORT=3000
    restart: unless-stopped
    depends_on:
      - homeassistant
```

## 🔧 Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HA_URL` | ✅ | - | Home Assistant URL (e.g., `http://homeassistant:8123`) |
| `HA_TOKEN` | ✅ | - | Home Assistant Long-Lived Access Token |
| `PORT` | ❌ | `3000` | Port to run the server on |
| `RUST_LOG` | ❌ | `info` | Log level (`error`, `warn`, `info`, `debug`, `trace`) |

### Getting a Home Assistant Token

1. Go to your Home Assistant web interface
2. Click on your profile (bottom left)
3. Scroll down to "Long-Lived Access Tokens"
4. Click "Create Token"
5. Give it a name like "TRMNL Entity Renderer"
6. Copy the token and use it as `HA_TOKEN`

## 📟 TRMNL Integration

### Basic TRMNL Usage

```bash
# Power monitoring dashboard
curl "http://localhost:3000/trmnl?sensors=sensor.power_production,sensor.power_usage&title=POWER%20STATUS" -o power.png

# System monitoring with gauges
curl "http://localhost:3000/trmnl?sensors=sensor.cpu_percent,sensor.memory_percent,sensor.disk_percent&title=SYSTEM%20STATUS" -o system.png

# Environmental sensors
curl "http://localhost:3000/trmnl?sensors=sensor.temperature,sensor.humidity_percent&title=ENVIRONMENT" -o environment.png
```

### Home Assistant Automation

Create automations to update TRMNL displays:

```yaml
# automations.yaml
automation:
  - alias: "Update TRMNL Power Display"
    trigger:
      - platform: time_pattern
        minutes: "/5"  # Every 5 minutes
    action:
      - service: shell_command.update_trmnl_power
        
  - alias: "Update TRMNL System Display"
    trigger:
      - platform: time_pattern
        minutes: "/10"  # Every 10 minutes
    action:
      - service: shell_command.update_trmnl_system

# configuration.yaml
shell_command:
  update_trmnl_power: >
    curl -s "http://ha-trmnl-renderer:3000/trmnl?sensors=sensor.power_production,sensor.power_usage,sensor.battery_percent&title=POWER%20STATUS" 
    -o /config/www/trmnl_power.png
    
  update_trmnl_system: >
    curl -s "http://ha-trmnl-renderer:3000/trmnl?sensors=sensor.cpu_percent,sensor.memory_percent,sensor.temperature&title=SYSTEM%20STATUS" 
    -o /config/www/trmnl_system.png
```

## 🔄 Updates and Maintenance

### Updating to Latest Version

```bash
# Stop current container
docker stop ha-trmnl-renderer
docker rm ha-trmnl-renderer

# Pull latest image
docker pull ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest

# Restart with same configuration
docker run -d \
  --name ha-trmnl-renderer \
  -p 3000:3000 \
  -e HA_URL=http://your-homeassistant:8123 \
  -e HA_TOKEN=your_token \
  --restart unless-stopped \
  ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
```

### With Docker Compose

```bash
# Pull latest and restart
docker-compose pull
docker-compose up -d
```

### Version Pinning

For production, pin to specific versions:

```yaml
services:
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:v1.0.0  # Specific version
    # ... rest of config
```

## 📊 Monitoring and Troubleshooting

### Health Checks

```bash
# Check container status
docker ps

# Check container health
docker inspect ha-trmnl-renderer | grep -A 10 Health

# Manual health check
curl -f http://localhost:3000/health
```

### Logs

```bash
# View logs
docker logs ha-trmnl-renderer

# Follow logs in real-time
docker logs -f ha-trmnl-renderer

# Last 100 lines
docker logs --tail 100 ha-trmnl-renderer
```

### Common Issues

**Container won't start:**
```bash
# Check if port is in use
netstat -tulpn | grep :3000

# Check environment variables
docker inspect ha-trmnl-renderer | grep -A 20 Env
```

**Home Assistant connection issues:**
```bash
# Test HA connectivity from container
docker exec ha-trmnl-renderer curl -H "Authorization: Bearer $HA_TOKEN" http://your-ha:8123/api/

# Check if HA URL is accessible
ping homeassistant.local
```

**Performance issues:**
```bash
# Check container resources
docker stats ha-trmnl-renderer

# Increase log level for debugging
docker run ... -e RUST_LOG=debug ...
```

## 🏗️ Building from Source

If you want to build your own image:

```bash
# Clone repository
git clone https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway.git
cd home-assistant-trmnl-entity-renderer-throwaway

# Build image
docker build -t ha-trmnl-renderer .

# Run your custom build
docker run -d \
  --name ha-trmnl-renderer \
  -p 3000:3000 \
  -e HA_URL=http://your-homeassistant:8123 \
  -e HA_TOKEN=your_token \
  ha-trmnl-renderer
```

## 🔒 Security Considerations

1. **Token Security**: Store HA tokens in `.env` files, not in docker-compose.yml
2. **Network Security**: Use docker networks to isolate containers
3. **Updates**: Regularly update to latest versions for security patches
4. **Access Control**: Restrict access to port 3000 using firewalls if needed

### Secure Network Setup

```yaml
version: '3.8'
networks:
  homeassistant:
    driver: bridge

services:
  homeassistant:
    networks:
      - homeassistant
    # ... HA config
    
  ha-trmnl-renderer:
    image: ghcr.io/akarras/home-assistant-trmnl-entity-renderer-throwaway:latest
    networks:
      - homeassistant
    environment:
      - HA_URL=http://homeassistant:8123  # Use service name
      - HA_TOKEN=${HA_TOKEN}
    # Don't expose port publicly, only to HA network
```

## 📝 Production Checklist

- [ ] HA_TOKEN is properly secured (not in version control)
- [ ] Health checks are configured
- [ ] Logging is set to appropriate level
- [ ] Container restart policy is set
- [ ] Monitoring/alerting is configured
- [ ] Backup strategy for configuration
- [ ] Update strategy is planned
- [ ] Network security is configured
- [ ] Resource limits are set if needed

## 🆘 Support

If you encounter issues:

1. Check the [GitHub Issues](https://github.com/akarras/home-assistant-trmnl-entity-renderer-throwaway/issues)
2. Review container logs for error messages
3. Test endpoints manually with curl
4. Verify Home Assistant connectivity and token permissions
5. Check if your entities exist and have the expected units