#!/bin/bash

# Source configuration file
CONFIG_FILE="$(dirname "$0")/config.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found!"
    exit 1
fi
source "$CONFIG_FILE"

# Function to URL encode strings
urlencode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$string'''))"
}

# Function to prompt user for retry
prompt_retry() {
    local message="$1"
    echo -e "\n${message}"
    echo "1) Retry sending message"
    echo "2) Continue without message"
    echo "3) Exit script"
    read -p "Choose an option (1-3): " choice
    case "$choice" in
        1) return 0 ;;    # retry
        2) return 2 ;;    # continue
        *) return 1 ;;    # exit
    esac
}

# Function to validate Telegram configuration
validate_telegram_config() {
    # Check if token is in correct format
    if [[ ! "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid bot token format. Should be like '123456789:ABCdefGHI-JklMNOpqrsTUVwxyz'"
        return 1
    fi

    # Test bot token and chat ID
    local test_response=$(curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getChat" \
        -d "chat_id=$TELEGRAM_CHAT_ID")
    
    if echo "$test_response" | grep -q "\"ok\":false"; then
        echo "Error: Telegram configuration invalid!"
        echo "Response: $test_response"
        echo -e "\nPossible solutions:"
        echo "1. Verify your bot token is correct"
        echo "2. Make sure you've started a chat with the bot"
        echo "3. For group chats, add the bot to the group"
        echo "4. For group chats, make sure to use the correct group chat ID (should start with -)"
        return 1
    fi
    return 0
}

# Function to delete Telegram message with timeout
delete_telegram_message() {
    local message_id="$1"
    timeout 5 curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/deleteMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "message_id=$message_id" >/dev/null 2>&1 || true
}

# Add message queue handling
declare -A message_queue
message_queue_index=0
last_message_time=0

# Function to handle rate limiting
check_rate_limit() {
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_message_time))
    if [ $time_diff -lt 1 ]; then  # Minimum 1 second between messages
        sleep 1
    fi
    last_message_time=$current_time
}

# Improved send_telegram_message function
send_telegram_message() {
    # Skip if telegram is not configured properly
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Skipping Telegram notification (not configured)"
        return 0
    fi
    
    # Validate config on first message
    if [ -z "$TELEGRAM_VALIDATED" ]; then
        if ! validate_telegram_config; then
            prompt_result=$(prompt_retry "Telegram configuration validation failed. What would you like to do?")
            case "$prompt_result" in
                0) export TELEGRAM_VALIDATED=1 ;;  # Continue anyway
                2) return 0 ;;                     # Skip Telegram
                *) exit 1 ;;                       # Exit
            esac
        else
            export TELEGRAM_VALIDATED=1
        fi
    fi
    
    message="$(urlencode "$1")"
    local max_retries=3
    local retry_count=0
    
    # Add to message queue
    message_queue[$message_queue_index]="$message"
    local current_index=$message_queue_index
    message_queue_index=$((message_queue_index + 1))
    
    # Rate limiting
    check_rate_limit
    
    while [ $retry_count -lt $max_retries ]; do
        echo "Attempting to send Telegram message (attempt $((retry_count + 1))/$max_retries)..."
        
        # Use timeout for curl request
        response=$(timeout 10 curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            -d "text=$message" \
            -d "parse_mode=HTML" 2>&1)
        
        http_code=$(echo "$response" | tail -n1)
        api_response=$(echo "$response" | head -n-1)
        
        if [ "$http_code" = "200" ]; then
            echo "Message sent successfully!"
            return 0
        else
            # Handle error codes
            case "$http_code" in
                403)
                    error_message="Bot was blocked by the user or group."
                    ;;
                404)
                    error_message="Bot token is invalid or chat not found."
                    ;;
                429)
                    error_message="Too many requests. Rate limit exceeded."
                    sleep 5  # Wait before retry
                    ;;
                *)
                    error_message="Unknown error occurred (HTTP $http_code)"
                    ;;
            esac
            
            echo -e "\nError: $error_message"
            prompt_result=$(prompt_retry "Failed to send message: $error_message\nResponse: $api_response")
            case "$prompt_result" in
                0) 
                    retry_count=$((retry_count + 1))
                    sleep 2  # Wait before retry
                    ;;
                2) 
                    echo "Continuing without sending message..."
                    return 0 
                    ;;
                *) 
                    echo "Exiting due to user request"
                    exit 1 
                    ;;
            esac
        fi
    done
    
    echo "Failed to send Telegram message after $max_retries attempts."
    prompt_retry "Max retries exceeded. What would you like to do?"
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
    if [ ! -d "$CUSTOM_PATCHES_DIR" ]; then
        send_telegram_message "⚠️ Patches directory not found: $CUSTOM_PATCHES_DIR"
        return 1
    fi

    # Loop through patch mapping
    for patch_file in "${!PATCH_MAPPING[@]}"; do
        patch_path="$CUSTOM_PATCHES_DIR/$patch_file"
        target_path="$ROM_DIR/${PATCH_MAPPING[$patch_file]}"
        
        if [ ! -f "$patch_path" ]; then
            send_telegram_message "⚠️ Patch file not found: $patch_file"
            continue
        fi
        
        if [ ! -d "$target_path" ]; then
            send_telegram_message "⚠️ Target path not found: ${PATCH_MAPPING[$patch_file]}"
            continue
        fi
        
        cd "$target_path"
        if git apply --check "$patch_path" &>/dev/null; then
            git apply "$patch_path"
            check_status "Applying patch $patch_file to ${PATCH_MAPPING[$patch_file]}"
        else
            send_telegram_message "❌ Patch $patch_file cannot be applied cleanly to ${PATCH_MAPPING[$patch_file]}"
            if [ "$IGNORE_PATCH_FAILURES" != "true" ]; then
                return 1
            fi
        fi
    done
}

# Function to safely write output
safe_output() {
    # Ignore broken pipe errors when writing output
    (echo "$@") 2>/dev/null || true
}

# Modify monitor_log function
monitor_log() {
    local log_file="$1"
    local pid="$2"
    local last_line=""
    local error_patterns=("FAILED:" "ERROR:" "fatal:" "failed." "error:")
    
    while kill -0 "$pid" 2>/dev/null; do
        if [ -f "$log_file" ]; then
            current_line=$(tail -n 1 "$log_file" 2>/dev/null || true)
            if [ "$current_line" != "$last_line" ]; then
                # Check for errors
                for pattern in "${error_patterns[@]}"; do
                    if echo "$current_line" | grep -qi "$pattern" 2>/dev/null; then
                        send_telegram_message "⚠️ Potential error detected:\n$current_line" || true
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
    
    # Start build with enhanced process protection
    (
        # Ignore hangup signals
        trap "" SIGHUP
        
        # Start the build process
        nohup nice -n 10 make $BUILD_TARGET -j$(nproc --all) > >(tee "$log_file") 2>&1 &
        build_pid=$!
        
        # Detach process from terminal
        disown $build_pid
        
        # Set process group and adjust priorities
        setpgrp $build_pid
        ionice -c 2 -n 7 -p $build_pid
        
        # Write PID to file for recovery
        echo $build_pid > "$ROM_DIR/.build_pid"
        
        # Wait for build in background
        wait $build_pid
    ) &
    main_build_pid=$!
    disown $main_build_pid
    
    # Start log monitoring in background with similar protection
    (
        trap "" SIGHUP
        monitor_log "$log_file" $build_pid
    ) &
    monitor_pid=$!
    disown $monitor_pid
    
    # Wait for build to complete
    wait $main_build_pid
    build_status=$?
    
    # Cleanup
    rm -f "$ROM_DIR/.build_pid"
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
        {
            error_log=$(tail -n 10 "$log_file" 2>/dev/null)
            send_telegram_message "❌ Build failed!\n\nLast few lines:\n$error_log" || true
        } 2>/dev/null
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
        send_telegram_message "⚠️ Build process interrupted! Exit code: $exit_code" || true
    fi
    # Kill background jobs more gracefully
    jobs -p | xargs -r kill -TERM 2>/dev/null || true
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
