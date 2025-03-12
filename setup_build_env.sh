#!/bin/bash

LATEST_MAKE_VERSION="4.4"
CCACHE_SIZE="50G"

# Error handling
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Source configuration file if it exists
CONFIG_FILE="$(dirname "$0")/config.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    # Override CCACHE_SIZE if defined in config
    [ ! -z "${CCACHE_SIZE_CONFIG:-}" ] && CCACHE_SIZE="$CCACHE_SIZE_CONFIG"
fi

# Detect Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
echo -e "${GREEN}Detected Ubuntu version: ${UBUNTU_VERSION}${NC}"

# Verify supported version
if (( $(echo "$UBUNTU_VERSION < 20.04" | bc -l) )); then
    echo -e "${RED}Unsupported Ubuntu version. Please use Ubuntu 20.04 or newer.${NC}"
    exit 1
fi

# Install apt-fast for faster package installation
if ! command -v apt-fast &> /dev/null; then
    echo -e "${GREEN}Installing apt-fast...${NC}"
    sudo add-apt-repository -y ppa:apt-fast/stable
    sudo apt update
    echo debconf apt-fast/maxdownloads string 16 | sudo debconf-set-selections
    echo debconf apt-fast/dlflag boolean true | sudo debconf-set-selections
    echo debconf apt-fast/aptmanager string apt | sudo debconf-set-selections
    sudo apt install -y apt-fast
fi

# Install required packages
echo -e "${GREEN}Installing required packages...${NC}"
sudo apt-fast install -y \
    bc bison build-essential curl flex g++-multilib gcc-multilib git gnupg gperf \
    imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool \
    libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop \
    openjdk-8-jdk pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev \
    ccache

# Install specific make version if needed
if ! make --version | grep -q "$LATEST_MAKE_VERSION"; then
    echo -e "${GREEN}Installing make $LATEST_MAKE_VERSION...${NC}"
    wget http://ftp.gnu.org/gnu/make/make-$LATEST_MAKE_VERSION.tar.gz
    tar -xvf make-$LATEST_MAKE_VERSION.tar.gz
    cd make-$LATEST_MAKE_VERSION
    ./configure
    make -j$(nproc)
    sudo make install
    cd ..
    rm -rf make-$LATEST_MAKE_VERSION make-$LATEST_MAKE_VERSION.tar.gz
fi

# Setup ccache
if [ ! -d "$HOME/.ccache" ]; then
    echo -e "${GREEN}Setting up ccache...${NC}"
    ccache -M "$CCACHE_SIZE"
fi

# Create build directory
echo -e "${GREEN}Creating build directory...${NC}"
[ -z "${ROM_DIR:-}" ] && ROM_DIR="$HOME/android/rom"
mkdir -p "$ROM_DIR"

# Save environment variables to config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}Creating initial config file...${NC}"
    cat > "$CONFIG_FILE" << EOF
# Build environment configuration
CCACHE_SIZE_CONFIG="$CCACHE_SIZE"
ROM_DIR="$ROM_DIR"
# Telegram settings
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"

DEVICE_CODENAME="your_device_codename"
CUSTOM_PATCHES_DIR="$HOME/patches"
ROM_MANIFEST_URL="YOUR_ROM_MANIFEST_URL"

# Build configuration
BUILD_TYPE="userdebug"    # Can be user, userdebug, or eng
BUILD_TARGET="bacon"      # Can be bacon, bootimage, recoveryimage, etc.
BUILD_CLEAN="false"       # Set to "true" to make clean before building

# Additional settings (optional)
CCACHE_ENABLED="true"
CCACHE_SIZE="$CCACHE_SIZE"

# Operation control
ENABLE_CCACHE="false"     # Enable/disable ccache setup
ENABLE_SYNC="false"       # Enable/disable source sync
ENABLE_PATCHES="true"     # Enable/disable patch applying

# Patches configuration
ENABLE_PATCHES="true"
CUSTOM_PATCHES_DIR="$(dirname "$0")/patches"

# Patch mapping (format: patch_file:target_path)
declare -A PATCH_MAPPING=(
    ["hardware_interfaces.patch"]="hardware/lineage/interfaces" # Example
    ["device_patch.patch"]="device/vendor/device"
    ["kernel_patch.patch"]="kernel/vendor/device"
)

# Custom build commands (optional)
# Leave empty to use defaults
# Example: CUSTOM_BUILD_COMMAND="mka bacon -j16"
CUSTOM_BUILD_COMMAND=""

# Custom lunch command (optional)
# Leave empty to use default: lunch ${DEVICE_CODENAME}_${BUILD_TYPE}
# Example: CUSTOM_LUNCH_COMMAND="lunch lineage_devicename-userdebug"
CUSTOM_LUNCH_COMMAND=""

# Upload settings
ENABLE_UPLOAD="true"
UPLOAD_TO="sourceforge"    # sourceforge, pixeldrain, gofile, or all
SOURCEFORGE_USER="username"
SOURCEFORGE_PROJECT="project"
SOURCEFORGE_API_KEY="your_api_key"
PIXELDRAIN_API_KEY="your_api_key"
EOF
fi

# Final setup message
echo -e "${GREEN}Setup completed! Some important notes:${NC}"
echo "1. Use 'repo init -u <manifest_url> -b <branch>' to initialize your ROM repository"
echo "2. Use 'repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags' to sync sources"
echo "3. Make sure to source build/envsetup.sh before building"
echo "4. Ensure you have at least 200GB of free space"
echo "5. RAM requirements: minimum 16GB recommended"
echo "6. Configuration file: $CONFIG_FILE"
echo "7. Build directory: $ROM_DIR"

# Make script executable
chmod +x "$(dirname "$0")/build_rom.sh"