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

# Function to edit Telegram message with timeout
edit_telegram_message() {
    local message_id="$1"
    local new_text="$2"
    local max_retries=3
    local retry_count=0
    
    # Skip if telegram is not configured
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Skipping message edit (Telegram not configured)"
        return 0
    fi
    
    # Validate message ID
    if [[ ! "$message_id" =~ ^[0-9]+$ ]]; then
        echo "Invalid message ID format: $message_id"
        return 1
    fi
    
    # Rate limiting
    check_rate_limit "edit_$message_id"
    
    while [ $retry_count -lt $max_retries ]; do
        echo "Attempting to edit message $message_id (attempt $((retry_count + 1))/$max_retries)..."
        
        response=$(timeout 5 curl -s -w "\n%{http_code}" \
            "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/editMessageText" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            -d "message_id=$message_id" \
            -d "text=$new_text" \
            -d "parse_mode=HTML")
            
        http_code=$(echo "$response" | tail -n1)
        api_response=$(echo "$response" | head -n-1)
        
        if [ "$http_code" = "200" ]; then
            echo "Message $message_id edited successfully"
            return 0
        else
            case "$http_code" in
                400) 
                    echo "Message not found or no changes in content"
                    return 0
                    ;;
                403)
                    echo "Bot lacks permission to edit messages"
                    return 1
                    ;;
                429)
                    echo "Rate limit exceeded, waiting..."
                    sleep 3
                    ;;
                *)
                    echo "Failed to edit message (HTTP $http_code)"
                    ;;
            esac
            
            retry_count=$((retry_count + 1))
            [ $retry_count -lt $max_retries ] && sleep 2
        fi
    done
    
    echo "Failed to edit message after $max_retries attempts"
    return 1
}

# Add message queue handling
declare -A message_queue
declare -A message_timestamps
message_queue_index=0
last_message_time=0
last_message_content=""
duplicate_delay=60  # Delay in seconds before allowing duplicate messages

# Function to handle rate limiting
check_rate_limit() {
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_message_time))
    
    # Enforce minimum delay between messages
    if [ $time_diff -lt 1 ]; then
        sleep 1
    fi
    
    # Check for duplicate message
    if [ "$1" = "$last_message_content" ]; then
        local last_sent=${message_timestamps["$1"]:-0}
        local since_last=$((current_time - last_sent))
        
        if [ $since_last -lt $duplicate_delay ]; then
            echo "Skipping duplicate message (sent ${since_last}s ago)"
            return 1
        fi
    fi
    
    message_timestamps["$1"]=$current_time
    last_message_content="$1"
    last_message_time=$current_time
    return 0
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
    
    # Check rate limit and duplicates
    if ! check_rate_limit "$1"; then
        return 0
    fi
    
    # Add to message queue
    message_queue[$message_queue_index]="$message"
    local current_index=$message_queue_index
    message_queue_index=$((message_queue_index + 1))
    
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
            # Extract message ID from response
            message_id=$(echo "$api_response" | jq -r '.result.message_id')
            if [[ "$message_id" =~ ^[0-9]+$ ]]; then
                (
                    sleep 2
                    # Update message with a checkmark to indicate completion
                    new_text="$message ✓"
                    edit_telegram_message "$message_id" "$(urlencode "$new_text")"
                ) &
            fi
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
        [ -n "$STATUS_MESSAGE_ID" ] && edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✅ $1 completed successfully!")"
    else
        [ -n "$STATUS_MESSAGE_ID" ] && edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "❌ Error: $1 failed!")"
        exit 1
    fi
}

# Setup ccache if enabled
setup_ccache() {
    if [ "$CCACHE_ENABLED" = "true" ]; then
        export USE_CCACHE=1
        export CCACHE_EXEC=/usr/bin/ccache
        ccache -M "$CCACHE_SIZE"
        [ -n "$STATUS_MESSAGE_ID" ] && edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✅ CCACHE configured with size $CCACHE_SIZE")"
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

# Function to safely write output with multiline support
safe_output() {
    while IFS= read -r line || [ -n "$line" ]; do
        echo "$line" 2>/dev/null || true
    done <<< "$@"
}

# Enhanced monitor_log function
monitor_log() {
    local log_file="$1"
    local pid="$2"
    local last_line=""
    local start_time=$(date +%s)
    local last_update=0
    local current_stage=""
    local error_count=0
    local warning_count=0
    local status_message_id=""
    local building_since=""
    
    # Initial status message
    response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$(urlencode "🔄 Building ROM...\n⏱️ Started at: $(date +'%H:%M:%S')")" \
        -d "parse_mode=HTML")
    status_message_id=$(echo "$response" | jq -r '.result.message_id')

    while kill -0 "$pid" 2>/dev/null; do
        if [ -f "$log_file" ]; then
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            
            # Get last few lines for context
            mapfile -t last_lines < <(tail -n 5 "$log_file" 2>/dev/null || true)
            current_line="${last_lines[-1]}"
            
            if [ "$current_line" != "$last_line" ]; then
                # Build status message
                status_text="🔄 Building ROM...\n"
                status_text+="⏱️ Running for: ${elapsed}s\n"
                status_text+="❌ Errors: $error_count\n"
                status_text+="⚠️ Warnings: $warning_count\n"
                
                if [ -n "$current_stage" ]; then
                    status_text+="\n📍 Current stage: $current_stage"
                fi
                
                # Update status message instead of sending new one
                edit_telegram_message "$status_message_id" "$(urlencode "$status_text")"
                
                # Only send new message for errors
                for pattern in "${error_patterns[@]}"; do
                    if echo "${last_lines[*]}" | grep -qi "$pattern"; then
                        error_count=$((error_count + 1))
                        context=$(printf '%s\n' "${last_lines[@]}")
                        send_telegram_message "⚠️ Build issue detected (#$error_count):\n<pre>$context</pre>"
                        break
                    fi
                done
                
                last_line="$current_line"
            fi
        fi
        sleep 2
    done
    
    # Final status update
    status_text="✨ Build completed!\n"
    status_text+="⏱️ Duration: ${elapsed}s\n"
    status_text+="❌ Errors: $error_count\n"
    status_text+="⚠️ Warnings: $warning_count"
    edit_telegram_message "$status_message_id" "$(urlencode "$status_text")"
}

# Build ROM with monitoring
build_rom() {
    cd "$ROM_DIR" || { send_telegram_message "❌ Failed to change to ROM directory!"; exit 1; }
    
    # Source build environment and setup
    if ! source build/envsetup.sh 2>/dev/null; then
        send_telegram_message "❌ Failed to source build environment!"
        exit 1
    fi
    
    # Custom lunch command with validation
    if [ -n "$CUSTOM_LUNCH_COMMAND" ]; then
        if ! eval "$CUSTOM_LUNCH_COMMAND"; then
            send_telegram_message "❌ Failed to configure build target!"
            exit 1
        fi
    else
        if ! lunch "${DEVICE_CODENAME}_${BUILD_TYPE}" 2>/dev/null; then
            send_telegram_message "❌ Failed to configure build target!"
            exit 1
        fi
    fi
    
    # Optional clean
    if [ "$BUILD_CLEAN" = "true" ]; then
        make clean && make clobber
        check_status "Clean build"
    fi
    
    # Create log file with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$ROM_DIR/build_log_${timestamp}.txt"
    local start_time=$(date +%s)
    local error_count=0
    
    # Send initial status message
    local status_text="🏗️ ROM Build Started\n"
    status_text+="⏱️ Started: $(date +'%H:%M:%S')\n"
    status_text+="📱 Device: $DEVICE_CODENAME\n"
    status_text+="🔄 Status: Initializing..."
    
    local status_response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$(urlencode "$status_text")" \
        -d "parse_mode=HTML")
    local status_message_id=$(echo "$status_response" | jq -r '.result.message_id')
    
    # Start build process
    {
        ${CUSTOM_BUILD_COMMAND:-m "$BUILD_TARGET" -j$(nproc --all)} 2>&1 | tee "$log_file"
    } &
    
    build_pid=$!
    
    # Monitor build process
    while kill -0 $build_pid 2>/dev/null; do
        if [ -f "$log_file" ]; then
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local last_lines=$(tail -n 3 "$log_file" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            
            # Update status message
            local status_text="🏗️ ROM Build In Progress\n"
            status_text+="⏱️ Runtime: $(printf '%dh:%dm:%ds' $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)))\n"
            status_text+="❌ Errors: $error_count\n"
            status_text+="\n📝 Recent output:\n<pre>$last_lines</pre>"
            
            # Try to edit message, on failure recreate it
            if ! edit_telegram_message "$status_message_id" "$(urlencode "$status_text")"; then
                local new_response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                    -d "chat_id=$TELEGRAM_CHAT_ID" \
                    -d "text=$(urlencode "$status_text")" \
                    -d "parse_mode=HTML")
                status_message_id=$(echo "$new_response" | jq -r '.result.message_id')
            fi
            
            # Check for errors without sending additional messages
            if echo "$last_lines" | grep -qiE 'error:|failed:|fatal:'; then
                error_count=$((error_count + 1))
            fi
        fi
        sleep 15
    done
    
    # Wait for build completion and update final status
    wait $build_pid
    local build_status=$?
    local final_time=$(($(date +%s) - start_time))
    
    local final_text="🏗️ ROM Build "
    if [ $build_status -eq 0 ]; then
        final_text+="Completed ✅\n"
    else
        final_text+="Failed ❌\n"
    fi
    final_text+="⏱️ Total time: $(printf '%dh:%dm:%ds' $((final_time/3600)) $((final_time%3600/60)) $((final_time%60)))\n"
    final_text+="❌ Total errors: $error_count"
    
    edit_telegram_message "$status_message_id" "$(urlencode "$final_text")"
    
    if [ $build_status -eq 0 ] && [ "$ENABLE_UPLOAD" = "true" ]; then
        upload_rom || return 1
    fi
    
    [ $build_status -eq 0 ] || exit 1
}

# Upload functions for different platforms
upload_to_sourceforge() {
    local file="$1"
    local filename=$(basename "$file")
    
    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "📤 Uploading to SourceForge: $filename")"
    
    scp -i ~/.ssh/id_rsa "$file" \
        "$SOURCEFORGE_USER@frs.sourceforge.net:/home/frs/project/$SOURCEFORGE_PROJECT/" 
    
    check_status "SourceForge upload"
    
    # Generate download link
    local download_url="https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/$filename"
    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✅ Upload complete!\n📥 Download: $download_url")"
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

# Function to upload to all supported platforms
upload_to_all_platforms() {
    local file="$1"
    local success=0
    local failed=()

    send_telegram_message "🚀 Starting multi-platform upload..."

    # SourceForge
    if [ ! -z "$SOURCEFORGE_API_KEY" ]; then
        if upload_to_sourceforge "$file"; then
            ((success++))
        else
            failed+=("SourceForge")
        fi
    fi

    # PixelDrain
    if [ ! -z "$PIXELDRAIN_API_KEY" ]; then
        if upload_to_pixeldrain "$file"; then
            ((success++))
        else
            failed+=("PixelDrain")
        fi
    fi

    # GoFile (no credentials needed)
    if upload_to_gofile "$file"; then
        ((success++))
    else
        failed+=("GoFile")
    fi

    # Send summary
    local total_platforms=3
    local failed_str=""
    if [ ${#failed[@]} -gt 0 ]; then
        failed_str="\n❌ Failed platforms: ${failed[*]}"
    fi
    
    send_telegram_message "📊 Upload Summary:\n✅ Successful: $success/$total_platforms$failed_str"
    
    return $([ $success -gt 0 ])
}

# Modify existing upload_rom function
upload_rom() {
    local rom_file="$ROM_DIR/out/target/product/$DEVICE_CODENAME/$BUILD_TARGET.zip"
    
    if [ ! -f "$rom_file" ]; then
        send_telegram_message "❌ ROM file not found for upload!"
        return 1
    fi
    
    case "$UPLOAD_TO" in
        "all")
            upload_to_all_platforms "$rom_file"
            ;;
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
    trap cleanup EXIT INT TERM
    
    # Create initial status message and store ID globally
    local initial_text="🚀 ROM Build Process\n"
    initial_text+="⏱️ Started: $(date +'%H:%M:%S')\n"
    initial_text+="📱 Device: $DEVICE_CODENAME\n\n"
    initial_text+="📋 Build Configuration:\n"
    initial_text+="• CCACHE: $([ "$ENABLE_CCACHE" = "true" ] && echo "✅ Enabled" || echo "⏭️ Skipped")\n"
    initial_text+="• Source Sync: $([ "$ENABLE_SYNC" = "true" ] && echo "✅ Enabled" || echo "⏭️ Skipped")\n"
    initial_text+="• Patches: $([ "$ENABLE_PATCHES" = "true" ] && echo "✅ Enabled" || echo "⏭️ Skipped")\n\n"
    initial_text+="🛠️ Built with ROMCraft"
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$(urlencode "$initial_text")" \
        -d "parse_mode=HTML")
    export STATUS_MESSAGE_ID=$(echo "$response" | jq -r '.result.message_id')
    
    [ "$ENABLE_CCACHE" = "true" ] && setup_ccache
    [ "$ENABLE_SYNC" = "true" ] && sync_source
    [ "$ENABLE_PATCHES" = "true" ] && apply_patches
    
    build_rom || {
        edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "❌ Build or upload process failed!\n\n🛠️ Built with ROMCraft")"
        exit 1
    }
    
    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✨ ROM build and upload process completed!\n\n🛠️ Built with ROMCraft")"
}

# Execute main function
main
