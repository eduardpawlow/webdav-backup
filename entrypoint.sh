#!/bin/bash

# Check necessary environment variables
if [ -z "$WEBDAV_URL" ] || [ -z "$WEBDAV_USERNAME" ] || [ -z "$WEBDAV_PASSWORD" ] || [ -z "$BACKUP_DIRS" ] || [ -z "$BACKUP_INTERVAL" ]; then
    echo "Error: Missing necessary environment variables"
    exit 1
fi

# Check Telegram related environment variables
if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    TELEGRAM_ENABLED=true
    echo "Telegram notifications enabled"
else
    TELEGRAM_ENABLED=false
    echo "Telegram notifications disabled"
fi

# Check encryption related environment variables
if [ -n "$ENCRYPTION_PASSWORD" ]; then
    ENCRYPTION_ENABLED=true
    echo "Backup encryption enabled"
else
    ENCRYPTION_ENABLED=false
    echo "Backup encryption disabled"
fi

create_folders_by_filepath() {
    local path="${1#/}" # delete the first slash if there is

    IFS='/' read -ra parts <<< "$path"

    folder_path=""
    for ((i = 0; i < ${#parts[@]} - 1; i++)); do
        folder_path="${folder_path}/${parts[i]}"
        full_path="${WEBDAV_URL}${folder_path}"

        curl -s -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" -X MKCOL $full_path -o /dev/null
    done
}

# Function to send Telegram messages
send_telegram_message() {
    if [ "$TELEGRAM_ENABLED" = true ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="$1" \
            -d parse_mode="HTML")
        
        body=$(echo "$response" | sed '$d')
        status_code=$(echo "$response" | tail -n1)
        
        if [ "$status_code" = "200" ]; then
            echo "Telegram message sent successfully"
        else
            echo "Failed to send Telegram message. Status code: $status_code, Response: $body"
        fi
    fi
}

echo "Starting backup task..."
echo "Backup task name: ${BACKUP_TASK_NAME}"
echo "Backup directories: ${BACKUP_DIRS}"
echo "Backup interval: ${BACKUP_INTERVAL} minutes"
echo "WebDAV URL: ${WEBDAV_URL}"
echo "WebDAV username: ${WEBDAV_USERNAME}"
echo "WebDAV path: ${WEBDAV_PATH}"

# Send startup notification
startup_message="<b>WebDAV Backup Task Started</b>%0A"
startup_message+="Task Name: ${BACKUP_TASK_NAME}%0A"
startup_message+="Backup Directories: ${BACKUP_DIRS}%0A"
startup_message+="Backup Interval: ${BACKUP_INTERVAL} minutes%0A"
startup_message+="WebDAV URL: ${WEBDAV_URL}%0A"
startup_message+="WebDAV Path: ${WEBDAV_PATH}"

send_telegram_message "$startup_message"

# Validate BACKUP_SPLIT_SIZE format
validate_split_size() {
    if [[ ! $BACKUP_SPLIT_SIZE =~ ^[0-9]+[bkmgtBKMGT]?$ ]]; then
        echo "Error: Invalid BACKUP_SPLIT_SIZE format. Please use a number followed by an optional unit suffix (b, k, m, g, t). For example: 100M, 1G, 500K"
        exit 1
    fi
}

# Set file split size, if not set then do not split
BACKUP_SPLIT_SIZE=${BACKUP_SPLIT_SIZE:-}

if [ -n "$BACKUP_SPLIT_SIZE" ]; then
    validate_split_size
    echo "File split size: ${BACKUP_SPLIT_SIZE}"
else
    echo "Files will not be split"
fi

# Function to encrypt files
encrypt_file() {
    local input_file="$1"
    local output_file="$1"  # Keep the output file name the same as the input file name

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        echo "Encrypting file: ${input_file}"
        openssl enc -aes-256-cbc -pbkdf2 -salt -in "$input_file" -out "${input_file}.tmp" -k "$ENCRYPTION_PASSWORD"
        mv "${input_file}.tmp" "$output_file"
    fi
}

# Function to upload files
upload_file() {
    local file="$1"
    local remote_path="$2"

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        encrypt_file "$file"
    fi

    create_folders_by_filepath "${WEBDAV_PATH}/${remote_path}"

    HTTP_CODE=$(curl -#L -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
            -T "$file" \
            "${WEBDAV_URL}${WEBDAV_PATH}/${remote_path}" \
            --connect-timeout 30 \
            --max-time 3600 \
            -w "%{http_code}" \
            -o /dev/null)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "Upload completed: ${remote_path}"
    else
        error_message="Error: Unable to upload file ${remote_path}. HTTP status code: ${HTTP_CODE}"
        echo "$error_message"
        send_telegram_message "<b>WebDAV Backup Failed</b>%0ATask Name: ${BACKUP_TASK_NAME}%0A${error_message}"
    fi
}

# Infinite loop to perform backups
while true; do
    # Get current date
    CURRENT_DATE=$(date +"%Y/%m/%d")
    
    # Create backup file name
    BACKUP_FILE="backup_$(date +"%Y%m%d_%H%M%S").tar.gz"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)

    # Print time
    echo "---------- $CURRENT_DATE ----------"
        
    echo "Compressing backup directories..."
    
    # Create backup file list
    BACKUP_LIST_FILE="${TEMP_DIR}/${BACKUP_FILE}.txt"
    
    if [ -n "$BACKUP_SPLIT_SIZE" ]; then
        tar -czf - --absolute-names ${BACKUP_DIRS} | split -b ${BACKUP_SPLIT_SIZE} - "${TEMP_DIR}/${BACKUP_FILE}.part-"
        for part in "${TEMP_DIR}/${BACKUP_FILE}.part-"*; do
            echo "$(basename "$part")" >> "$BACKUP_LIST_FILE"
        done
    else
        tar -czf "${TEMP_DIR}/${BACKUP_FILE}" --absolute-names ${BACKUP_DIRS}
    fi
    
    echo "Compression completed, starting upload..."
    
    # Upload files (may be multiple split files)
    if [ -n "$BACKUP_SPLIT_SIZE" ]; then
        for part in "${TEMP_DIR}/${BACKUP_FILE}.part-"*; do
            upload_file "$part" "${CURRENT_DATE}/$(basename "$part")"
        done
        # Upload backup file list
        upload_file "$BACKUP_LIST_FILE" "${CURRENT_DATE}/${BACKUP_FILE}.txt"
    else
        upload_file "${TEMP_DIR}/${BACKUP_FILE}" "${CURRENT_DATE}/${BACKUP_FILE}"
    fi
    
    # Clean up temporary files
    rm -rf "${TEMP_DIR}"

    echo "--------------------------------"
    
    # Wait for the next backup
    echo "Waiting ${BACKUP_INTERVAL} minutes before the next backup..."
    sleep $((BACKUP_INTERVAL * 60))
done
