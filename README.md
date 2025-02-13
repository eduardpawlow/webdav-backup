# WebDAV Backup Tool

This tool can regularly back up specified directories to a WebDAV server and provide recovery functionality. It supports file encryption and decryption.

## Features

- Scheduled backups of specified directories
- Upload backup files to the WebDAV server
- Configurable backup interval
- Support for large file splitting
- Restore specified backup files from the WebDAV server
- Support for Telegram notifications (on startup and backup failures)
- Customizable backup task names
- Support for backup file encryption and decryption

## Usage

### Backup

```bash
docker run -d \
  -e WEBDAV_URL="https://your-webdav-server.com/backup" \
  -e WEBDAV_USERNAME="your_username" \
  -e WEBDAV_PASSWORD="your_password" \
  -e ENCRYPTION_PASSWORD="your_encryption_password" \
  -v /path/to/data:/data \
  ghcr.io/monlor/webdav-backup:main
```

### Restore

To restore a backup, follow these steps:

1. Ensure the backup container is running. If it is not running, use the command above to start it.

2. Enter the running container:

```bash
docker exec -it <container_id_or_name> /bin/bash
```

3. Execute the restore script inside the container:

```bash
/restore.sh
```

4. Follow the prompts to enter the name of the backup file to restore. The format can be:
   - `backup_YYYYMMDD_HHMMSS.tar.gz` (un-split backup file)
   - `backup_YYYYMMDD_HHMMSS.tar.gz.txt` (list of split backup files)

5. Confirm the restore operation and wait for it to complete.

## Environment Variables

- `WEBDAV_URL`: URL of the WebDAV server (required), format: https://your-webdav-server.com/dav
- `WEBDAV_USERNAME`: Username for the WebDAV server (required)
- `WEBDAV_PASSWORD`: Password for the WebDAV server (required)
- `WEBDAV_PATH`: Backup path on the WebDAV server, default is empty, format: /backup
- `BACKUP_DIRS`: Directories to back up, separated by spaces, default is "/data"
- `BACKUP_INTERVAL`: Backup interval (minutes), default is 60 minutes
- `BACKUP_TASK_NAME`: Name of the backup task, default is "Default Backup Task"
- `BACKUP_SPLIT_SIZE`: Size for splitting backup files (optional). Format is a number followed by an optional unit suffix (b, k, m, g, t). For example: 100M, 1G, 500K. If not set, backup files will not be split.
- `TELEGRAM_BOT_TOKEN`: Token for the Telegram Bot (optional)
- `TELEGRAM_CHAT_ID`: Chat ID for receiving Telegram notifications (optional)
- `ENCRYPTION_PASSWORD`: Password for encrypting backup files (optional). If this variable is set, backup files will be encrypted.

## Notes

- Ensure the WebDAV server has enough storage space
- Regularly check if backups are successful
- Consider implementing a backup file rotation or cleanup mechanism to prevent the WebDAV server from running out of storage space
- The restore operation will overwrite existing data in the target directory, please proceed with caution
- Before performing a restore operation, ensure you have sufficient permissions to access and modify the target directory
- If Telegram notifications are configured, the program will send a notification message containing all important parameters at startup
- If Telegram notifications are configured, additional notifications will only be sent in case of backup failures
- When using `BACKUP_SPLIT_SIZE`, backup files will be split into multiple parts, and a same-named .txt file list will be created
- During restoration, you can use either the .tar.gz file name (un-split) or the .tar.gz.txt file name (split file list)
- If `ENCRYPTION_PASSWORD` is set, backup files will be encrypted. Ensure to use the same password during restoration.
- The names of encrypted files remain unchanged, meaning the file names seen on the WebDAV server are the same as when unencrypted.
- When restoring encrypted backups, the correct `ENCRYPTION_PASSWORD` must be provided; otherwise, the restoration will fail.

## Contribution

Contributions, issues, and pull requests are welcome.

## License

This project is licensed under the MIT License. Please refer to the [LICENSE](LICENSE) file for details.
