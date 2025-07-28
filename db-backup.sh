#!/bin/bash

# Script to create timestamped database backups
# This script creates a backup of the 'default' database in the db-backups-archive folder
# Usage: ./db-backup.sh [custom_name]

set -e  # Exit on any error

# Configuration
BACKUP_DIR="db-backups-archive"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
FILENAME_TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DEFAULT_BACKUP_NAME="db_backup_${FILENAME_TIMESTAMP}.sql"

# Parse command line arguments
CUSTOM_NAME="$1"
if [[ -n "$CUSTOM_NAME" ]]; then
    BACKUP_FILE="${BACKUP_DIR}/${CUSTOM_NAME}_${FILENAME_TIMESTAMP}.sql"
else
    BACKUP_FILE="${BACKUP_DIR}/${DEFAULT_BACKUP_NAME}"
fi

# Function to print usage
print_usage() {
    echo "Usage: $0 [custom_name]"
    echo ""
    echo "Options:"
    echo "  custom_name  Optional prefix for the backup file name"
    echo ""
    echo "Examples:"
    echo "  $0                    # Create backup: db-backups-archive/db_backup_YYYY-MM-DD_HH-MM-SS.sql"
    echo "  $0 before-migration   # Create backup: db-backups-archive/before-migration_YYYY-MM-DD_HH-MM-SS.sql"
    echo ""
    echo "Prerequisites:"
    echo "  - Docker and docker-compose must be installed"
    echo "  - The .env file must exist in the current directory (.env)"
    echo "  - Database service must be defined in docker-compose.yml"
    echo "  - Database 'default' must exist and be accessible"
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    print_usage
    exit 0
fi

# Validate that docker-compose.yml exists
if [[ ! -f "docker-compose.yml" ]]; then
    echo "Error: docker-compose.yml not found in current directory!"
    echo "Please run this script from the directory containing docker-compose.yml."
    exit 1
fi

# Validate that .env file exists in current directory
if [[ ! -f ".env" ]]; then
    echo "Error: Environment file '.env' not found!"
    echo "Please ensure the .env file exists in the current directory."
    exit 1
fi

# Create backup directory if it doesn't exist
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

echo "Database Backup Process"
echo "======================"
echo "Database: default"
echo "Backup file: $BACKUP_FILE"
echo "Timestamp: $TIMESTAMP"
echo "Environment: .env"
echo ""

# Check if the database exists and is accessible
echo "Checking database connectivity..."
DB_EXISTS=$(docker compose --env-file .env exec -T db psql -U twenty_user -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='default';" | tr -d ' \n\r')

if [[ "$DB_EXISTS" != "1" ]]; then
    echo "❌ Error: Database 'default' does not exist or is not accessible!"
    echo "Please ensure the database service is running and the 'default' database exists."
    exit 1
fi

echo "✅ Database 'default' is accessible."
echo ""

# Create the backup
echo "Creating database backup..."
echo "Running: pg_dump -U twenty_user default > $BACKUP_FILE"

docker compose --env-file .env exec -T db pg_dump -U twenty_user default > "$BACKUP_FILE"

if [[ $? -ne 0 ]]; then
    echo "❌ Error: Failed to create database backup!"
    # Clean up partial backup file if it exists
    if [[ -f "$BACKUP_FILE" ]]; then
        rm "$BACKUP_FILE"
        echo "Cleaned up partial backup file."
    fi
    exit 1
fi

# Verify the backup was created successfully
if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "❌ Error: Backup file was not created!"
    exit 1
fi

# Get backup file info
BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null || echo "unknown")
LINE_COUNT=$(wc -l < "$BACKUP_FILE")

# Verify backup is not empty
if [[ "$LINE_COUNT" -lt 10 ]]; then
    echo "⚠️  Warning: Backup file seems unusually small ($LINE_COUNT lines)."
    echo "Please verify the backup content manually."
fi

echo "✅ Database backup created successfully!"
echo ""

# Show backup information
echo "Backup Information:"
echo "  File: $BACKUP_FILE"
echo "  Size: $BACKUP_SIZE bytes"
echo "  Lines: $LINE_COUNT"
echo "  Created: $TIMESTAMP"
echo ""

# Show a preview of the backup
echo "Preview (first 10 lines):"
echo "========================="
head -10 "$BACKUP_FILE"

if [[ $LINE_COUNT -gt 10 ]]; then
    echo ""
    echo "... (showing first 10 lines of $LINE_COUNT total lines)"
fi

echo ""
echo "🎉 Database backup completed successfully!"
echo ""

# Step 4: Create symbolic link to latest backup
echo "Step 4: Creating symbolic link to latest backup..."
LATEST_LINK="db_backup_latest.sql"

# Remove existing symbolic link if it exists
if [[ -L "$LATEST_LINK" ]]; then
    rm "$LATEST_LINK"
    echo "Removed existing symbolic link: $LATEST_LINK"
fi

# Create new symbolic link
ln -s "$BACKUP_FILE" "$LATEST_LINK"

if [[ $? -eq 0 ]]; then
    echo "✅ Created symbolic link: $LATEST_LINK -> $BACKUP_FILE"
else
    echo "⚠️  Warning: Failed to create symbolic link to latest backup."
fi

echo ""

# Show existing backups
echo "Existing backups in $BACKUP_DIR:"
if ls "$BACKUP_DIR"/*.sql >/dev/null 2>&1; then
    ls -lah "$BACKUP_DIR"/*.sql | while read -r line; do
        echo "  $line"
    done
else
    echo "  No other backup files found."
fi

echo ""
echo "To restore from this backup:"
echo "  ./db-restore.sh $BACKUP_FILE"
echo ""
echo "To restore from the latest backup:"
echo "  ./db-restore.sh $LATEST_LINK"
echo ""
echo "To view the full backup content:"
echo "  cat $BACKUP_FILE"
echo "  # or"
echo "  less $BACKUP_FILE"
