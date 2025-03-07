# 🛠️ RomCraft Build System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Linux-blue.svg)](https://www.linux.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Bot-blue.svg)](https://core.telegram.org/bots)

An automated Android ROM building system featuring Telegram notifications, patch management, and multi-platform upload support.

## 📑 Table of Contents
- [Key Features](#key-features)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
- [Patch Management](#patch-management)
- [Telegram Integration](#telegram-integration)
- [Upload Support](#upload-support)
- [Configuration](#configuration)
- [Common Issues](#common-issues)

---

## ✨ Key Features
- Real-time build status notifications via Telegram
- Flexible patch management with directory mapping
- Efficient ccache handling
- Multi-platform ROM upload (SourceForge, PixelDrain, GoFile)
- Advanced build monitoring and error reporting

## 🚀 Quick Start
1. Clone the repository
2. Copy `config.conf.example` to `config.conf`
3. Configure settings:
```bash
# Essential Configuration
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
ROM_DIR="/path/to/rom"
DEVICE_CODENAME="your_device"
ROM_MANIFEST_URL="rom_manifest_url"
```

---

## 🧩 Core Components

### 📁 Patch System
Place patches in `patches/` and map in `config.conf`:
```bash
declare -A PATCH_MAPPING=(
   ["patch1.patch"]="target/path1"
   ["patch2.patch"]="target/path2"
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

## ⚠️ Error Handling

- Telegram send failures can be retried or skipped
- Failed patches can be ignored with `IGNORE_PATCH_FAILURES="true"`
- Build errors are reported with last 10 lines of log

---

## 🔧 Configuration Options

<details>
<summary>Build Settings</summary>

| Option | Description | Default |
|--------|-------------|---------|
| `ENABLE_CCACHE` | Enable compiler cache | `true` |
| `ENABLE_SYNC` | Sync source code | `true` |
| `ENABLE_PATCHES` | Apply custom patches | `true` |
| `ENABLE_UPLOAD` | Upload built ROM | `true` |
| `BUILD_CLEAN` | Clean build | `false` |

</details>

## Configuration

1. Edit `config.conf` with your settings

---

## 📋 Prerequisites

<details>
<summary>Required Packages</summary>

```bash
# Essential packages
sudo apt install git-core gnupg flex bison build-essential zip curl zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386
sudo apt install libncurses5 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip jq
```

</details>

- Linux build environment
- Telegram Bot Token and Chat ID
- jq package: `sudo apt install jq`
- curl: `sudo apt install curl`

## Upload Platform Setup

### SourceForge Setup

1. Generate SSH key if you don't have one:
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

2. Add SSH key to SourceForge:
   - Go to SourceForge account settings
   - Navigate to "SSH Settings"
   - Add your public key (content of `~/.ssh/id_rsa.pub`)

3. Project Access:
   - Create or join a project on SourceForge
   - Ensure you have developer access
   - Note your project name for config.conf

4. Test SSH access:
```bash
ssh -i ~/.ssh/id_rsa your_username@frs.sourceforge.net
```

### PixelDrain Setup

1. Create account at [PixelDrain](https://pixeldrain.com)
2. Get API key:
   - Go to account settings
   - Navigate to API section
   - Generate new API key
   - Add to config.conf: `PIXELDRAIN_API_KEY="your_key"`

## Directory Structure
```
setup/
├── build_rom.sh    # Main build script
├── config.conf     # Your configuration
└── patches/        # Custom patches (optional)
```

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

## 📝 License

This project is open source and available under the [MIT License](LICENSE).
