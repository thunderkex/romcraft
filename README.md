# 🛠️ RomCraft Build System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Linux-blue.svg)](https://www.linux.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Bot-blue.svg)](https://core.telegram.org/bots)
[![GitHub stars](https://img.shields.io/github/stars/thunderkex/romcraft?style=social)](https://github.com/thunderkex/romcraft/stargazers)
[![Docker Support](https://img.shields.io/badge/Docker-Support-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)

An automated Android ROM building system featuring Telegram notifications, patch management, and multi-platform upload support.

## 📑 Table of Contents
- [Key Features](#-key-features)
- [Quick Start](#-quick-start)
- [System Requirements](#-system-requirements)
- [Core Components](#-core-components)
- [Patch Management](#️-patch-management)
- [Telegram Integration](#-telegram-integration)
- [Upload Support](#️-upload-support)
- [Build Status Indicators](#-build-status-indicators)
- [ROM Build Process](#-rom-build-process)
- [Advanced Usage](#-advanced-usage)
- [Performance Tips](#-performance-tips)
- [Prerequisites](#-prerequisites)
- [Configuration](#-configuration)
- [Docker Support](#-docker-support)
- [Contributing](#-contributing)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)

---

## ✨ Key Features
- Real-time build status notifications via Telegram
- Flexible patch management with directory mapping
- Efficient ccache handling
- Multi-platform ROM upload (SourceForge, PixelDrain, GoFile)
- Advanced build monitoring and error reporting

## 🚀 Quick Start
1. Clone the repository:
   ```bash
   git clone https://github.com/thunderkex/romcraft.git
   cd romcraft
   ```
2. Copy `config.conf.example` to `config.conf`
   ```bash
   cp config.conf.example config.conf
   ```
3. Configure essential settings:
   ```bash
   # Essential Configuration
   TELEGRAM_BOT_TOKEN="your_bot_token"
   TELEGRAM_CHAT_ID="your_chat_id"
   ROM_DIR="/path/to/rom"
   DEVICE_CODENAME="your_device"
   ROM_MANIFEST_URL="rom_manifest_url"
   ```
4. Run the build:
   ```bash
   ./build_rom.sh
   ```

## 📊 System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU       | 4 cores | 8+ cores    |
| RAM       | 16GB    | 32GB+       |
| Storage   | 200GB   | 500GB+      |
| Internet  | 10Mbps  | 50Mbps+     |

---

## 🧩 Core Components

### 📁 Patch System
Place patches in `patches/` and map in `config.conf`:
```bash
declare -A PATCH_MAPPING=(
["hardware_interfaces.patch"]="hardware/lineage/interfaces"
["device_patch.patch"]="device/vendor/device"
["kernel_patch.patch"]="kernel/vendor/device"
)
```

### 🔨 Build Control
Run with: `./build_rom.sh`

./build_rom.sh

Options can be controlled via config.conf:
- `BUILD_CLEAN`: Clean build
- `ENABLE_CCACHE`: Use ccache
- `ENABLE_SYNC`: Sync sources
- `ENABLE_PATCHES`: Apply patches
- `ENABLE_UPLOAD`: Upload ROM

---

## 🛠️ Patch Management

Place your patches in the `patches/` directory and map them in config.conf:
```bash
patches/
├── hardware_interfaces.patch
├── device_patch.patch
└── kernel_patch.patch
```

Each patch needs an entry in `PATCH_MAPPING` pointing to its target directory.

---

## 💬 Telegram Integration

1. Create a bot using [@BotFather](https://t.me/botfather)
2. Get chat ID using [@userinfobot](https://t.me/userinfobot)
3. Configure in `config.conf`:
   ```bash
   TELEGRAM_BOT_TOKEN="123456789:ABCdefGHI..."
   TELEGRAM_CHAT_ID="your_chat_id"
   ```

---

## ☁️ Upload Support

<details>
<summary>Supported Platforms</summary>

| Platform | Features | Requirements |
|----------|----------|--------------|
| SourceForge | SSH upload, direct links | SSH key |
| PixelDrain | Fast upload, API support | API key |
| GoFile | No account needed, temporary | None |

</details>

Configure in `config.conf`:
```bash
ENABLE_UPLOAD="true"
UPLOAD_TO="platform_name"
```

---

## 🚦 Build Status Indicators

| Status | Description |
|--------|-------------|
| ✅ Success | Build completed successfully |
| ⚠️ Warning | Build completed with warnings |
| ❌ Error | Build failed |
| 🔄 In Progress | Build is running |
| 📤 Uploading | ROM upload in progress |

---

## 📊 ROM Build Process
Example of real-time build status display:

```
🚀 ROM Build Process
⏱️ Started: 14:30:45
⌛ Runtime: 0h:15m:30s
📱 Device: example_device

📋 Build Status:
• ✅ Setup
• ✅ Source Sync
• 🔄 Patches
• ⏳ Build
• ⏳ Upload

📝 Current: Applying patch 3/10...
```

The build process display provides real-time information about:
- Build start time and duration
- Target device
- Step-by-step progress
- Current operation details

---

## 🔍 Advanced Usage

### Custom Build Flags
```bash
BUILD_FLAGS=(
    "TARGET_BUILD_VARIANT=userdebug"
    "TARGET_USES_CUSTOM_FLAGS=true"
    "WITH_GMS=false"
)
```

### Patch Application Order
1. Device-specific patches
2. Framework patches
3. Vendor patches
4. Custom patches

---

## 📈 Performance Tips

- Enable ccache for faster rebuilds
- Use SSD storage for build directory
- Configure optimal thread count (`-j` flag)
- Keep ROM sources on local storage

---

## 📋 Prerequisites

### Required for First Run
```bash
chmod +x setup_build_env.sh
./setup_build_env.sh
```

### Additional Prerequisites
- Telegram Bot Token ([Setup Guide](#telegram-bot-setup))
- Platform-specific upload credentials
- SSH key for SourceForge uploads
- Stable Internet connection

## 🔧 Configuration

Edit `config.conf` with your settings:

| Option | Description | Required Value |
|--------|-------------|----------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot authentication token | Required |
| `TELEGRAM_CHAT_ID` | Telegram chat identifier | Required |
| `ROM_DIR` | Path to ROM source directory | Required |
| `DEVICE_CODENAME` | Device codename for build | Required |
| `ENABLE_CCACHE` | Enable compiler caching | `true` |
| `ENABLE_SYNC` | Enable source code syncing | `true` |
| `ENABLE_PATCHES` | Enable patch application | `true` |
| `ENABLE_UPLOAD` | Enable ROM uploading | `true` |
| `BUILD_CLEAN` | Perform clean build | `false` |
| `UPLOAD_TO` | Target upload platform | Optional |

## 🐋 Docker Support

```bash
# Build and run with volume mounts
docker build -t romcraft .
docker run -v /path/to/rom:/rom \
          -v /path/to/ccache:/ccache \
          -v $(pwd)/config.conf:/app/config.conf \
          romcraft
```

---

## 🤝 Contributing

We welcome contributions! Please follow these steps:
1. Fork the repository
2. Create a feature branch
3. Submit a Pull Request

---

## Common Issues

### SourceForge Upload Fails
- Check SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
- Verify project access rights
- Test SSH connection manually

### PixelDrain Upload Fails
- Verify API key is valid
- Check file size limits
- Ensure account is active

## Telegram Bot Setup

1. Create bot via [@BotFather](https://t.me/BotFather)
2. Get bot token and add to config
3. Get chat ID:
   - Send message to [@userinfobot](https://t.me/userinfobot)
   - Add ID to config: `TELEGRAM_CHAT_ID="your_id"`

---

## 🔍 Troubleshooting

### Build Failures
- Check available disk space
- Verify RAM usage
- Review build logs in `build/logs`

### Upload Issues
- Test network connectivity
- Verify platform credentials
- Check file permissions

### Patch Application Errors
- Ensure clean working directory
- Check patch format compatibility
- Verify target directories exist

---

## 📝 License

This project is open source and available under the [MIT License](LICENSE).

---

<p align="center">
Made with ❤️ for the Android community
</p>
