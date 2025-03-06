# RomCraft Build System

An automated Android ROM building system featuring Telegram notifications, patch management, and multi-platform upload support.

## Key Features
- Real-time build status notifications via Telegram
- Flexible patch management with directory mapping
- Efficient ccache handling
- Multi-platform ROM upload (SourceForge, PixelDrain, GoFile)
- Advanced build monitoring and error reporting

## Quick Start
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

## Core Components

### Patch System
Place patches in `patches/` and map in `config.conf`:
```bash
declare -A PATCH_MAPPING=(
   ["patch1.patch"]="target/path1"
   ["patch2.patch"]="target/path2"
)
```

### Build Control
Run with: `./build_rom.sh`

./build_rom.sh
```

Options can be controlled via config.conf:
- `BUILD_CLEAN`: Clean build
- `ENABLE_CCACHE`: Use ccache
- `ENABLE_SYNC`: Sync sources
- `ENABLE_PATCHES`: Apply patches
- `ENABLE_UPLOAD`: Upload ROM

## Patch Management

Place your patches in the `patches/` directory and map them in config.conf:
```bash
patches/
├── hardware_interfaces.patch
├── device_patch.patch
└── kernel_patch.patch
```

Each patch needs an entry in `PATCH_MAPPING` pointing to its target directory.

## Telegram Integration

1. Create a bot using [@BotFather](https://t.me/botfather)
2. Get chat ID using [@userinfobot](https://t.me/userinfobot)
3. Configure in `config.conf`:
   ```bash
   TELEGRAM_BOT_TOKEN="123456789:ABCdefGHI..."
   TELEGRAM_CHAT_ID="your_chat_id"
   ```

## Upload Support

Supported platforms:
- SourceForge
- PixelDrain
- GoFile

Configure in `config.conf`:
```bash
ENABLE_UPLOAD="true"
UPLOAD_TO="platform_name"
```

## Error Handling

- Telegram send failures can be retried or skipped
- Failed patches can be ignored with `IGNORE_PATCH_FAILURES="true"`
- Build errors are reported with last 10 lines of log

## About the Name

ROMCraft represents:
- **ROM**: Custom ROM building focus
- **Craft**: Professional crafting/building process
- The combination implies a toolset for crafting ROMs professionally

## Configuration

1. Edit `config.conf` with your settings

## Prerequisites

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

## Configuration Options

### Build Control
- `ENABLE_CCACHE`: Enable/disable ccache
- `ENABLE_SYNC`: Enable/disable source sync
- `ENABLE_PATCHES`: Enable/disable patch applying
- `ENABLE_UPLOAD`: Enable/disable file upload
- `BUILD_CLEAN`: Enable/disable clean build

### Upload Options
- `UPLOAD_TO`: Choose upload platform
  - "sourceforge"
  - "pixeldrain"
  - "gofile"

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

## License

This project is open source and available under the MIT License.
