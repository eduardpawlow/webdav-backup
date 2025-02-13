FROM alpine:latest

LABEL MAINTAINER me@monlor.com
LABEL VERSION 1.1.2

# Install necessary tools
RUN apk add --no-cache bash curl tar gzip openssl && mkdir -p /data

# Copy scripts to the container
COPY --chmod=755 *.sh /

# Set environment variables
ENV BACKUP_INTERVAL="60"
ENV BACKUP_DIRS="/data"
ENV BACKUP_TASK_NAME="Default Backup Task"

# Run the script
CMD ["/entrypoint.sh"]
