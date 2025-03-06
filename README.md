# ROMCraft

> Automated ROM building and distribution toolkit with integrated notifications and multi-platform upload support.

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

## Usage

Basic usage:
```bash
./build_rom.sh
```

With specific options example:
```bash
ENABLE_SYNC=true ENABLE_CCACHE=true ./build_rom.sh
```

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
