# Quick Start Guide

## 🚀 Get Started in 3 Minutes

### 1. Setup Environment

Copy the example environment file:

**Windows (Command Prompt/PowerShell):**
```cmd
copy .env.example .env
```

**Linux/macOS:**
```bash
cp .env.example .env
```

Edit `.env` with your Home Assistant details:
```env
HA_URL=http://your-home-assistant:8123
HA_TOKEN=your_long_lived_access_token
PORT=3000
```

> 💡 The application automatically loads the `.env` file - no need to source it manually!

### 2. Get Your Home Assistant Token

1. Open Home Assistant web interface
2. Click your profile (bottom left)
3. Scroll to "Long-Lived Access Tokens"
4. Click "Create Token"
5. Name it "Image Server"
6. Copy the token to your `.env` file

### 3. Run the Server

**Option A: Windows Users**
```cmd
# Command Prompt
run.bat

# Or PowerShell (recommended)
.\run.ps1
```

**Option B: Linux/macOS Users**
```bash
chmod +x run.sh
./run.sh
```

**Option C: Direct cargo run (any platform)**
```bash
cargo run
```

The server starts at `http://localhost:3000` and automatically loads your `.env` file!

## 🧪 Test Your Setup

### Quick Test
Open `test.html` in your browser or visit:
- Health: http://localhost:3000/health
- Cameras: http://localhost:3000/cameras

### Command Line Tests

**Windows:**
```cmd
# Use curl if available, or use the test.html in browser
curl http://localhost:3000/health
```

**Linux/macOS:**
```bash
chmod +x test.sh
./test.sh
```

## 📷 Common Usage Examples

### Camera Snapshots
```
GET http://localhost:3000/image/entity/camera.front_door
GET http://localhost:3000/image/entity/camera.living_room
```

### Person Pictures
```
GET http://localhost:3000/image/entity/person.john
GET http://localhost:3000/image/entity/person.admin
```

### Weather Icons
```
GET http://localhost:3000/image/entity/weather.home
```

### Custom URLs
```
GET http://localhost:3000/image/url?url=/local/images/floorplan.png
```

## 🐳 Docker Quick Start

**Windows:**
```cmd
copy .env.example .env
REM Edit .env with your details
docker-compose up --build
```

**Linux/macOS:**
```bash
cp .env.example .env
# Edit .env with your details
docker-compose up --build
```

## 🔧 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Connection refused" | Check HA_URL in .env file |
| "403 Forbidden" | Verify HA_TOKEN is correct in .env |
| "404 Not Found" | Entity doesn't exist or has no image |
| Server won't start | Check if port 3000 is available |
| ".env not loading" | Ensure .env file is in project root |
| "HA_TOKEN not set" | Check .env file format (no quotes needed) |

### Windows-Specific Notes
- Use `run.bat` or `run.ps1` for best experience
- PowerShell script (`run.ps1`) provides better error handling
- No need to install additional tools to load environment variables

## 📋 Entity Discovery

1. Visit http://localhost:3000/cameras to see all cameras
2. Check Home Assistant Developer Tools > States
3. Look for entities with `entity_picture` attributes

## 🎯 Next Steps

- Read the full [README.md](README.md) for detailed documentation
- Check available endpoints and features
- Integrate with your applications
- Set up reverse proxy for production use

---

**Need help?** 
- Add `RUST_LOG=debug` to your `.env` file for detailed logs
- Windows: Use `.\run.ps1 -Debug` for debug mode
- Or run: `cargo run` (loads .env automatically)
