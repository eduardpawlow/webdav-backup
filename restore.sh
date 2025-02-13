#!/bin/bash

set -e

# Set WebDAV related information using environment variables
WEBDAV_URL="${WEBDAV_URL}"
WEBDAV_USERNAME="${WEBDAV_USERNAME}"
WEBDAV_PASSWORD="${WEBDAV_PASSWORD}"
WEBDAV_PATH="${WEBDAV_PATH:-}"
BACKUP_DIRS="${BACKUP_DIRS}"

# Temporary directory for downloading backup files
TEMP_DIR=$(mktemp -d)

# Check encryption password
if [ -n "$ENCRYPTION_PASSWORD" ]; then
    ENCRYPTION_ENABLED=true
    echo "Backup decryption enabled"
else
    ENCRYPTION_ENABLED=false
    echo "Backup decryption disabled"
fi

# Function: Get backup filename from user input
get_backup_filename() {
    read -p "Please enter the name of the backup file to restore (format: backup_YYYYMMDD_HHMMSS.tar.gz or backup_YYYYMMDD_HHMMSS.tar.gz.txt): " BACKUP_FILE
    if [[ ! $BACKUP_FILE =~ ^backup_[0-9]{8}_[0-9]{6}\.tar\.gz(\.txt)?$ ]]; then
        echo "Error: Invalid filename format."
        exit 1
    fi
}

# Function: Parse date from backup filename and construct full path
construct_backup_path() {
    local filename="$1"
    local date_part=$(echo $filename | sed -E 's/^backup_([0-9]{8})_.*/\1/')
    local year=${date_part:0:4}
    local month=${date_part:4:2}
    local day=${date_part:6:2}
    BACKUP_PATH="${WEBDAV_URL}${WEBDAV_PATH}/${year}/${month}/${day}/${filename}"
}

# Function: Download and decrypt backup file from WebDAV
download_and_decrypt_backup() {
    local backup_path="$1"
    local output_file="$2"
    echo "Downloading file from WebDAV: $backup_path"
    HTTP_CODE=$(curl -#L -w "%{http_code}" -o "$output_file" \
                    -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
                    "${backup_path}")

    if [ "$HTTP_CODE" = "200" ]; then
        echo "File downloaded successfully."
        if [ "$ENCRYPTION_ENABLED" = true ]; then
            echo "Decrypting file..."
            openssl enc -d -aes-256-cbc -pbkdf2 -in "$output_file" -out "${output_file}.tmp" -k "$ENCRYPTION_PASSWORD"
            mv "${output_file}.tmp" "$output_file"
        fi
    else
        echo "Error: File download failed. HTTP status code: ${HTTP_CODE}"
        return 1
    fi
}

# Function: Remove existing files
remove_existing_files() {
    echo "Removing existing files..."
    IFS=' ' read -ra DIRS <<< "$BACKUP_DIRS"
    for dir in "${DIRS[@]}"; do
        if [ -d "$dir" ]; then
            find "$dir" -mindepth 1 -delete
            echo "Cleared directory: $dir"
        else
            echo "Warning: Directory does not exist: $dir"
        fi
    done
}

# Main program starts
if [ -z "$1" ]; then
    get_backup_filename
else
    BACKUP_FILE="$1"
    if [[ ! $BACKUP_FILE =~ ^backup_[0-9]{8}_[0-9]{6}\.tar\.gz(\.txt)?$ ]]; then
        echo "Error: Invalid filename format."
        exit 1
    fi
fi

construct_backup_path "$BACKUP_FILE"

if [[ $BACKUP_FILE == *.txt ]]; then
    # Download backup list file
    BACKUP_LIST_FILE="${TEMP_DIR}/${BACKUP_FILE}"
    if ! download_and_decrypt_backup "$BACKUP_PATH" "$BACKUP_LIST_FILE"; then
        echo "Error: Unable to download backup list file."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Read backup list and download files
    while IFS= read -r file_name; do
        file_url="${BACKUP_PATH%/*}/${file_name}"
        output_file="${TEMP_DIR}/${file_name}"
        
        if ! download_and_decrypt_backup "$file_url" "$output_file"; then
            echo "Error: Unable to download file $file_name"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    done < "$BACKUP_LIST_FILE"

    # If there are multiple files, merge them first
    if ls "${TEMP_DIR}/${BACKUP_FILE%.txt}.part-"* 1> /dev/null 2>&1; then
        echo "Merging split backup files..."
        cat "${TEMP_DIR}/${BACKUP_FILE%.txt}.part-"* > "${TEMP_DIR}/${BACKUP_FILE%.txt}"
    fi

    BACKUP_FILE="${BACKUP_FILE%.txt}"
else
    # Directly download a single backup file
    if ! download_and_decrypt_backup "$BACKUP_PATH" "${TEMP_DIR}/${BACKUP_FILE}"; then
        echo "Error: Unable to download backup file."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# Warn the user
echo "Warning: This operation will delete all existing data in the following directories and replace it with backup data:"
echo "$BACKUP_DIRS"
read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation canceled."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Remove existing files
remove_existing_files

# Start restoration
echo "Starting data restoration..."

tar -xzf "${TEMP_DIR}/${BACKUP_FILE}" -C / --absolute-names

if [ $? -eq 0 ]; then
    echo "Data restoration completed successfully."
else
    echo "Error: Data restoration failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"
