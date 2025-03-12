#!/bin/bash

# Source configuration file
CONFIG_FILE="$(dirname "$0")/config.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found! Please run setup_build_env.sh first."
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
    fi
}

# Consolidate status updates in sync_source
sync_source() {
    update_status "Checking ROM directory"
    if [ ! -d "$ROM_DIR" ]; then
        mkdir -p "$ROM_DIR"
        cd "$ROM_DIR"
        update_status "Initializing repo"
        repo init -u "$ROM_MANIFEST_URL" || {
            update_status "Repository initialization failed" "❌"
            return 1
        }
    fi
    cd "$ROM_DIR"
    update_status "Syncing source code"
    repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags || {
        update_status "Source sync failed" "❌"
        return 1
    }
    update_status "Source sync completed" "✅"
    return 0
}

# Update patch application status reporting
apply_patches() {
    if [ ! -d "$CUSTOM_PATCHES_DIR" ]; then
        update_status "Patches directory not found: $CUSTOM_PATCHES_DIR" "❌"
        return 1
    fi

    local patch_count=0
    local total_patches=${#PATCH_MAPPING[@]}
    
    update_status "Starting patch application (0/$total_patches)"
    
    for patch_file in "${!PATCH_MAPPING[@]}"; do
        patch_path="$CUSTOM_PATCHES_DIR/$patch_file"
        target_path="$ROM_DIR/${PATCH_MAPPING[$patch_file]}"
        
        update_status "Applying patch: $patch_file ($(($patch_count + 1))/$total_patches)"
        
        if [ ! -f "$patch_path" ]; then
            update_status "Patch file not found: $patch_file" "⚠️"
            continue
        fi
        
        if [ ! -d "$target_path" ]; then
            update_status "Target path not found: ${PATCH_MAPPING[$patch_file]}" "⚠️"
            continue
        fi
        
        cd "$target_path"
        if git apply --check "$patch_path" &>/dev/null; then
            if git apply "$patch_path"; then
                patch_count=$((patch_count + 1))
                update_status "Applied patch $patch_count/$total_patches: $patch_file" "✅"
            else
                update_status "Failed to apply patch: $patch_file" "❌"
                [ "$IGNORE_PATCH_FAILURES" != "true" ] && return 1
            fi
        else
            update_status "Patch cannot be applied cleanly: $patch_file" "❌"
            [ "$IGNORE_PATCH_FAILURES" != "true" ] && return 1
        fi
    done

    update_status "Patch application completed ($patch_count/$total_patches successful)" "✅"
    return 0
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

# Update build_rom status reporting
build_rom() {
    cd "$ROM_DIR" || {
        update_status "Failed to change to ROM directory" "❌"
        return 1
    }
    
    update_status "Sourcing build environment"
    if ! source build/envsetup.sh 2>/dev/null; then
        update_status "Failed to source build environment" "❌"
        return 1
    fi
    
    update_status "Configuring build target"
    if [ -n "$CUSTOM_LUNCH_COMMAND" ]; then
        if ! eval "$CUSTOM_LUNCH_COMMAND"; then
            update_status "Failed to configure build target" "❌"
            return 1
        fi
    else
        if ! lunch "${DEVICE_CODENAME}_${BUILD_TYPE}" 2>/dev/null; then
            update_status "Failed to configure build target" "❌"
            return 1
        fi
    fi
    
    if [ "$BUILD_CLEAN" = "true" ]; then
        update_status "Cleaning build directory"
        make clean && make clobber
    fi
    
    # Create log file with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$ROM_DIR/build_log_${timestamp}.txt"
    local start_time=$(date +%s)
    local error_count=0

    # Start build process
    {
        ${CUSTOM_BUILD_COMMAND:-m "$BUILD_TARGET" -j$(nproc --all)} 2>&1 | tee "$log_file"
    } &
    
    build_pid=$!
    
    # Use update_status with build monitoring
    update_status "Building ROM" "🔄" "$build_pid" "$log_file"
    
    # Wait for build completion
    wait $build_pid
    local build_status=$?
    local final_time=$(($(date +%s) - start_time))
    
    local final_text="🏗️ ROM Build "
    if [ $build_status -eq 0 ]; then
        final_text+="Completed ✅\n"
        # Add ROM file details if build succeeded
        local rom_file="$ROM_DIR/out/target/product/$DEVICE_CODENAME/$BUILD_TARGET.zip"
        if [ -f "$rom_file" ]; then
            local file_size=$(du -h "$rom_file" | cut -f1)
            local file_name=$(basename "$rom_file")
            final_text+="📦 File: $file_name\n"
            final_text+="💾 Size: $file_size\n"
        fi
    else
        final_text+="Failed ❌\n"
    fi
    final_text+="⏱️ Total time: $(printf '%dh:%dm:%ds' $((final_time/3600)) $((final_time%3600/60)) $((final_time%60)))\n"
    final_text+="❌ Total errors: $error_count\n"
    final_text+="📱 Device: $DEVICE_CODENAME\n"
    final_text+="🔄 Type: $BUILD_TYPE\n"
    [ -n "$BUILD_TARGET" ] && final_text+="🎯 Target: $BUILD_TARGET\n"
    final_text+="📅 Date: $(date +'%Y-%m-%d %H:%M:%S')"
    
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
    local test_mode="${TEST_UPLOAD:-false}"

    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "📤 Uploading to SourceForge: $filename")"

    if [ "$test_mode" = "true" ]; then
        echo "Test mode: Simulating SourceForge upload"
        download_links["sourceforge"]="https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/$filename"
        sleep 2
        return ${TEST_SOURCEFORGE_RESULT:-0}
    fi

    timeout 300 scp -i ~/.ssh/id_rsa "$file" \
        "$SOURCEFORGE_USER@frs.sourceforge.net:/home/frs/project/$SOURCEFORGE_PROJECT/" || return 1

    local download_url="https://sourceforge.net/projects/$SOURCEFORGE_PROJECT/files/$filename"
    download_links["sourceforge"]="$download_url"
    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✅ SourceForge upload complete!\n📥 Download: $download_url")"
    return 0
}

upload_to_pixeldrain() {
    local file="$1"
    local filename=$(basename "$file")
    local test_mode="${TEST_UPLOAD:-false}"

    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "📤 Uploading to PixelDrain: $filename")"

    if [ "$test_mode" = "true" ]; then
        echo "Test mode: Simulating PixelDrain upload"
        download_links["pixeldrain"]="https://pixeldrain.com/u/test_id"
        sleep 2
        return ${TEST_PIXELDRAIN_RESULT:-0}
    fi

    local response=$(timeout 300 curl -s -H "Authorization: Bearer $PIXELDRAIN_API_KEY" \
        -F "file=@$file" \
        https://pixeldrain.com/api/file)

    local id=$(echo $response | jq -r '.id')
    if [ ! -z "$id" ] && [ "$id" != "null" ]; then
        local download_url="https://pixeldrain.com/u/$id"
        download_links["pixeldrain"]="$download_url"
        edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✅ PixelDrain upload complete!\n📥 Download: $download_url")"
        return 0
    fi
    return 1
}

upload_to_gofile() {
    local file="$1"
    local filename=$(basename "$file")
    local test_mode="${TEST_UPLOAD:-false}"

    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "📤 Uploading to GoFile: $filename")"

    if [ "$test_mode" = "true" ]; then
        echo "Test mode: Simulating GoFile upload"
        download_links["gofile"]="https://gofile.io/d/test_id"
        sleep 2
        return ${TEST_GOFILE_RESULT:-0}
    fi

    local server=$(timeout 30 curl -s https://api.gofile.io/getServer | jq -r '.data.server')
    [ -z "$server" ] && return 1

    local response=$(timeout 300 curl -s -F "file=@$file" "https://$server.gofile.io/uploadFile")
    local download_url=$(echo $response | jq -r '.data.downloadPage')

    if [ ! -z "$download_url" ] && [ "$download_url" != "null" ]; then
        download_links["gofile"]="$download_url"
        edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "✅ GoFile upload complete!\n📥 Download: $download_url")"
        return 0
    fi
    return 1
}

# Function to upload to all supported platforms
upload_to_all_platforms() {
    local file="$1"
    local success=0
    local results=()
    local test_mode="${TEST_UPLOAD:-false}"

    if [ "$test_mode" = "true" ]; then
        echo "🚀 Starting multi-platform upload test..."
    else
        edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "🚀 Starting multi-platform upload...")"
    fi

    # SourceForge
    if [ ! -z "$SOURCEFORGE_API_KEY" ] || [ "$test_mode" = "true" ]; then
        if upload_to_sourceforge "$file"; then
            ((success++))
            results+=("✅ SourceForge")
        else
            results+=("❌ SourceForge")
        fi
    fi

    # PixelDrain
    if [ ! -z "$PIXELDRAIN_API_KEY" ] || [ "$test_mode" = "true" ]; then
        if upload_to_pixeldrain "$file"; then
            ((success++))
            results+=("✅ PixelDrain")
        else
            results+=("❌ PixelDrain")
        fi
    fi

    # GoFile
    if upload_to_gofile "$file"; then
        ((success++))
        results+=("✅ GoFile")
    else
        results+=("❌ GoFile")
    fi

    # Create status summary with download links
    local summary="📊 Upload Summary:\n"
    summary+="✅ Successful: $success/3\n\n"
    summary+="Status:\n"
    for result in "${results[@]}"; do
        summary+="$result\n"
    done

    summary+="\n📥 Download Links:\n"
    for platform in "${!download_links[@]}"; do
        summary+="• ${platform^}: ${download_links[$platform]}\n"
    done

    if [ "$test_mode" = "true" ]; then
        echo -e "$summary"
    else
        edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "$summary")"
    fi

    # Return success if at least one upload worked
    return $([ $success -gt 0 ])
}

# Modify existing upload_rom function
upload_rom() {
    local rom_file="$ROM_DIR/out/target/product/$DEVICE_CODENAME/$BUILD_TARGET.zip"
    
    if [ ! -f "$rom_file" ]; then
        update_status "ROM file not found for upload" "❌"
        return 1
    fi
    
    update_status "Starting ROM upload"
    case "$UPLOAD_TO" in
        "all")
            update_status "Uploading to all platforms"
            upload_to_all_platforms "$rom_file"
            ;;
        "sourceforge"|"pixeldrain"|"gofile")
            update_status "Uploading to $UPLOAD_TO"
            upload_to_${UPLOAD_TO} "$rom_file"
            ;;
        *)
            update_status "Invalid upload platform specified" "❌"
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

# Add new function for sending inline keyboard message
send_keyboard_message() {
    local text="$1"
    local keyboard='{
        "inline_keyboard": [
            [
                {"text": "🔌 Shutdown Server", "callback_data": "shutdown"},
                {"text": "⏯️ Keep Running", "callback_data": "continue"}
            ]
        ]
    }'
    
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$(urlencode "$text")" \
        -d "reply_markup=$keyboard" \
        -d "parse_mode=HTML"
}

# Function to update build status message with build monitoring
update_status() {
    local message="$1"
    local status="${2:-🔄}"
    local build_pid="${3:-}"
    local log_file="${4:-}"
    local current_time=$(date +%s)
    local elapsed=$((current_time - BUILD_START_TIME))
    
    # Update status text
    STATUS_TEXT="🚀 ROM Build Process\n"
    STATUS_TEXT+="⏱️ Started: $(date -d @$BUILD_START_TIME +'%H:%M:%S')\n"
    STATUS_TEXT+="⌛ Runtime: $(printf '%dh:%dm:%ds' $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)))\n"
    STATUS_TEXT+="📱 Device: $DEVICE_CODENAME\n\n"
    STATUS_TEXT+="📋 Build Status:\n"
    
    # Update stage status
    case "$status" in
        "✅") STAGE_STATUS["$CURRENT_STAGE"]="✅";;
        "❌") STAGE_STATUS["$CURRENT_STAGE"]="❌";;
        "🔄") STAGE_STATUS["$CURRENT_STAGE"]="🔄";;
    esac
    
    # Add all stages to status message
    for stage in "${STAGES[@]}"; do
        STATUS_TEXT+="• ${STAGE_STATUS[$stage]:-⏳} $stage\n"
    done
    
    # Monitor build process if pid and log file provided
    if [ -n "$build_pid" ] && [ -n "$log_file" ]; then
        while kill -0 "$build_pid" 2>/dev/null; do
            if [ -f "$log_file" ]; then
                current_time=$(date +%s)
                elapsed=$((current_time - BUILD_START_TIME))
                last_lines=$(tail -n 3 "$log_file" 2>&1 | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                
                # Update status text with build progress
                local build_status="🏗️ ROM Build In Progress\n"
                build_status+="⏱️ Runtime: $(printf '%dh:%dm:%ds' $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)))\n"
                build_status+="❌ Errors: $ERROR_COUNT\n"
                build_status+="\n📝 Recent output:\n<pre>$last_lines</pre>"
                
                STATUS_TEXT+="\n\n$build_status"
                
                # Try to edit message, on failure recreate it
                if ! edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "$STATUS_TEXT")"; then
                    local new_response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                        -d "chat_id=$TELEGRAM_CHAT_ID" \
                        -d "text=$(urlencode "$STATUS_TEXT")" \
                        -d "parse_mode=HTML")
                    STATUS_MESSAGE_ID=$(echo "$new_response" | jq -r '.result.message_id')
                fi
                
                # Check for errors without sending additional messages
                if echo "$last_lines" | grep -qiE 'error:|failed:|fatal:'; then
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                fi
            fi
            sleep 15
        done
    else
        # Add current operation details for non-build messages
        [ -n "$message" ] && STATUS_TEXT+="\n📝 Current: $message"
        # Add error count if any
        [ $ERROR_COUNT -gt 0 ] && STATUS_TEXT+="\n❌ Errors: $ERROR_COUNT"
        edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "$STATUS_TEXT")"
    fi
}

main() {
    trap cleanup EXIT INT TERM
    
    # Initialize build tracking variables
    export BUILD_START_TIME=$(date +%s)
    export ERROR_COUNT=0
    export STAGES=("Setup" "Source Sync" "Patches" "Build" "Upload")
    declare -A STAGE_STATUS
    
    # Create initial status message
    local initial_text="🚀 ROM Build Process Starting...\n"
    initial_text+="📱 Device: $DEVICE_CODENAME"
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$(urlencode "$initial_text")" \
        -d "parse_mode=HTML")
    export STATUS_MESSAGE_ID=$(echo "$response" | jq -r '.result.message_id')
    
    # Setup stage
    export CURRENT_STAGE="Setup"
    update_status "Initializing build environment"
    [ "$ENABLE_CCACHE" = "true" ] && setup_ccache
    update_status "Setup completed" "✅"
    
    # Source sync stage
    export CURRENT_STAGE="Source Sync"
    if [ "$ENABLE_SYNC" = "true" ]; then
        update_status "Syncing source code"
        sync_source || {
            update_status "Source sync failed" "❌"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            exit 1
        }
        update_status "Source sync completed" "✅"
    else
        update_status "Source sync skipped" "✅"
    fi
    
    # Patches stage
    export CURRENT_STAGE="Patches"
    if [ "$ENABLE_PATCHES" = "true" ]; then
        update_status "Applying patches"
        apply_patches || {
            update_status "Patch application failed" "❌"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            exit 1
        }
        update_status "Patches applied" "✅"
    else
        update_status "Patches skipped" "✅"
    fi
    
    # Build stage
    export CURRENT_STAGE="Build"
    update_status "Starting ROM build"
    build_rom || {
        update_status "Build failed" "❌"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        exit 1
    }
    update_status "Build completed" "✅"
    
    # Upload stage
    export CURRENT_STAGE="Upload"
    if [ "$ENABLE_UPLOAD" = "true" ]; then
        update_status "Uploading ROM"
        upload_rom || {
            update_status "Upload failed" "❌"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            exit 1
        }
        update_status "Upload completed" "✅"
    else
        update_status "Upload skipped" "✅"
    fi
    
    # Final status update
    STATUS_TEXT+="\n\n✨ Build process completed successfully!"
    edit_telegram_message "$STATUS_MESSAGE_ID" "$(urlencode "$STATUS_TEXT")"
    
    # Send shutdown option message
    send_keyboard_message "🤖 Build completed! Shutdown server?"
    
    # Wait for response (60 seconds timeout)
    local start_time=$(date +%s)
    while [ $(($(date +%s) - start_time)) -lt 60 ]; do
        response=$(curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getUpdates" \
            -d "offset=-1" \
            -d "timeout=1")
        
        if echo "$response" | grep -q "callback_data"; then
            if echo "$response" | grep -q '"callback_data":"shutdown"'; then
                send_telegram_message "🔌 Initiating server shutdown..."
                sleep 2
                sudo shutdown -h now
                break
            elif echo "$response" | grep -q '"callback_data":"continue"'; then
                send_telegram_message "⏯️ Server will continue running"
                break
            fi
        fi
        sleep 1
    done
}

# Add new test function
test_uploads() {
    local test_file="/tmp/test_rom.zip"
    
    # Create dummy file if it doesn't exist
    if [ ! -f "$test_file" ]; then
        dd if=/dev/zero of="$test_file" bs=1M count=100 >/dev/null 2>&1
    fi

    echo "🧪 Starting upload tests..."
    
    # Clear previous download links
    download_links=()
    
    case "$UPLOAD_TO" in
        "all")
            upload_to_all_platforms "$test_file"
            ;;
        "sourceforge"|"pixeldrain"|"gofile")
            upload_to_${UPLOAD_TO} "$test_file"
            echo -e "\n📥 Download Links:"
            for platform in "${!download_links[@]}"; do
                echo "• ${platform^}: ${download_links[$platform]}"
            done
            ;;
        *)
            echo "❌ Invalid upload platform specified!"
            return 1
            ;;
    esac
    rm -f "$test_file"
}

# Replace main execution with conditional
if [ "${TEST_UPLOAD:-false}" = "true" ]; then
    test_uploads
else
    main
fi
