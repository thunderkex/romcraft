#!/bin/bash

# Source configuration file
CONFIG_FILE="$(dirname "$0")/config.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found!"
    exit 1
fi
source "$CONFIG_FILE"

# Function to send message to Telegram
send_telegram_message() {
    message="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="HTML"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        send_telegram_message "✅ $1 completed successfully!"
    else
        send_telegram_message "❌ Error: $1 failed!"
        exit 1
    fi
}

# Setup ccache if enabled
setup_ccache() {
    if [ "$CCACHE_ENABLED" = "true" ]; then
        export USE_CCACHE=1
        export CCACHE_EXEC=/usr/bin/ccache
        ccache -M "$CCACHE_SIZE"
        send_telegram_message "✅ CCACHE configured with size $CCACHE_SIZE"
    fi
}

# Sync ROM source
sync_source() {
    if [ ! -d "$ROM_DIR" ]; then
        mkdir -p "$ROM_DIR"
        cd "$ROM_DIR"
        repo init -u "$ROM_MANIFEST_URL"
    fi
    cd "$ROM_DIR"
    repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
    check_status "Source sync"
}

# Apply patches
apply_patches() {
    if [ -d "$CUSTOM_PATCHES_DIR" ]; then
        cd "$ROM_DIR"
        for patch in "$CUSTOM_PATCHES_DIR"/*.patch; do
            if [ -f "$patch" ]; then
                git apply "$patch"
                check_status "Applying patch $(basename $patch)"
            fi
        done
    fi
}

# Log monitoring function
monitor_log() {
    local log_file="$1"
    local pid="$2"
    local last_line=""
    local error_patterns=("FAILED:" "ERROR:" "fatal:" "failed." "error:")
    
    while [ -d "/proc/$pid" ]; do
        if [ -f "$log_file" ]; then
            current_line=$(tail -n 1 "$log_file")
            if [ "$current_line" != "$last_line" ]; then
                # Check for errors
                for pattern in "${error_patterns[@]}"; do
                    if echo "$current_line" | grep -qi "$pattern"; then
                        send_telegram_message "⚠️ Potential error detected:\n$current_line"
                    fi
                done
                last_line="$current_line"
            fi
        fi
        sleep 5
    done
}

# Build ROM with monitoring
build_rom() {
    cd "$ROM_DIR"
    . build/envsetup.sh
    
    # Custom lunch command
    lunch "${DEVICE_CODENAME}_${BUILD_TYPE}"
    
    # Optional clean
    if [ "$BUILD_CLEAN" = "true" ]; then
        make clean
        make clobber
        check_status "Clean build"
    fi
    
    # Create log file
    local log_file="$ROM_DIR/build_log_$(date +%Y%m%d_%H%M%S).txt"
    send_telegram_message "📝 Build log: $log_file"
    
    # Start build with logging
    make $BUILD_TARGET -j$(nproc --all) 2>&1 | tee "$log_file" &
    build_pid=$!
    
    # Start log monitoring in background
    monitor_log "$log_file" "$build_pid" &
    monitor_pid=$!
    
    # Wait for build to complete
    wait $build_pid
    build_status=$?
    
    # Kill monitor process
    kill $monitor_pid 2>/dev/null
    
    # Check final status
    if [ $build_status -eq 0 ]; then
        send_telegram_message "✅ ROM build ($BUILD_TARGET) completed successfully!"
        
        # Send build size information
        if [ -f "$ROM_DIR/out/target/product/$DEVICE_CODENAME/$BUILD_TARGET.zip" ]; then
            size=$(du -h "$ROM_DIR/out/target/product/$DEVICE_CODENAME/$BUILD_TARGET.zip" | cut -f1)
            send_telegram_message "📦 Build size: $size"
            
            # Upload if enabled
            if [ "$ENABLE_UPLOAD" = "true" ]; then
                upload_rom
            fi
        fi
    else
        # Send last 10 lines of log on failure
        error_log=$(tail -n 10 "$log_file")
        send_telegram_message "❌ Build failed!\n\nLast few lines:\n$error_log"
        exit 1
    fi
}

# Upload functions for different platforms
upload_to_sourceforge() {
    local file="$1"
    local filename=$(basename "$file")
    
    send_telegram_message "📤 Uploading to SourceForge: $filename"
    
    scp -i ~/.ssh/id_rsa "$file" \
        "$SOURCEFORGE_USER@frs.sourceforge.net:/home/frs/project/$SOURCEFORGE_PROJECT/" 
    
    check_status "SourceForge upload"
    
    # Generate download link
    local download_url="https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/$filename"
    send_telegram_message "✅ Upload complete!\n📥 Download: $download_url"
}

upload_to_pixeldrain() {
    local file="$1"
    local filename=$(basename "$file")
    
    send_telegram_message "📤 Uploading to PixelDrain: $filename"
    
    response=$(curl -H "Authorization: Bearer $PIXELDRAIN_API_KEY" \
        -F "file=@$file" \
        https://pixeldrain.com/api/file)
    
    id=$(echo $response | jq -r '.id')
    if [ ! -z "$id" ]; then
        local download_url="https://pixeldrain.com/u/$id"
        send_telegram_message "✅ Upload complete!\n📥 Download: $download_url"
    else
        send_telegram_message "❌ PixelDrain upload failed!"
        return 1
    fi
}

upload_to_gofile() {
    local file="$1"
    local filename=$(basename "$file")
    
    send_telegram_message "📤 Uploading to GoFile: $filename"
    
    # Get best server
    server=$(curl -s https://api.gofile.io/getServer | jq -r '.data.server')
    
    # Upload file
    response=$(curl -F "file=@$file" "https://$server.gofile.io/uploadFile")
    
    download_url=$(echo $response | jq -r '.data.downloadPage')
    if [ ! -z "$download_url" ]; then
        send_telegram_message "✅ Upload complete!\n📥 Download: $download_url"
    else
        send_telegram_message "❌ GoFile upload failed!"
        return 1
    fi
}

# Upload ROM file
upload_rom() {
    local rom_file="$ROM_DIR/out/target/product/$DEVICE_CODENAME/$BUILD_TARGET.zip"
    
    if [ ! -f "$rom_file" ]; then
        send_telegram_message "❌ ROM file not found for upload!"
        return 1
    fi
    
    case "$UPLOAD_TO" in
        "sourceforge")
            upload_to_sourceforge "$rom_file"
            ;;
        "pixeldrain")
            upload_to_pixeldrain "$rom_file"
            ;;
        "gofile")
            upload_to_gofile "$rom_file"
            ;;
        *)
            send_telegram_message "❌ Invalid upload platform specified!"
            return 1
            ;;
    esac
}

# Add cleanup handler
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        send_telegram_message "⚠️ Build process interrupted! Exit code: $exit_code"
    fi
    kill $(jobs -p) 2>/dev/null
    exit $exit_code
}

# Main execution
main() {
    # Set cleanup handler
    trap cleanup EXIT INT TERM
    
    send_telegram_message "🚀 Starting ROM build process..."
    
    if [ "$ENABLE_CCACHE" = "true" ]; then
        setup_ccache
    else
        send_telegram_message "ℹ️ Skipping ccache setup (disabled in config)"
    fi
    
    if [ "$ENABLE_SYNC" = "true" ]; then
        sync_source
    else
        send_telegram_message "ℹ️ Skipping source sync (disabled in config)"
    fi
    
    if [ "$ENABLE_PATCHES" = "true" ]; then
        apply_patches
    else
        send_telegram_message "ℹ️ Skipping patches (disabled in config)"
    fi
    
    build_rom
    
    send_telegram_message "✨ ROM build process completed!"
}

# Execute main function
main
