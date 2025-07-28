#!/bin/bash

# Script to restore database from db_dump.sql
# This script drops all content of the /default db and restores from the dump file
# Usage: ./db-restore.sh [dump_filename]

set -e  # Exit on any error

# Configuration
DEFAULT_DUMP_FILE="db_backup_latest.sql"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Parse command line arguments
DUMP_FILE="${1:-$DEFAULT_DUMP_FILE}"

# Function to print usage
print_usage() {
    echo "Usage: $0 [dump_filename]"
    echo ""
    echo "Options:"
    echo "  dump_filename  Name of the SQL dump file (default: db_backup_latest.sql)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Restore from db_backup_latest.sql"
    echo "  $0 my-backup.sql      # Restore from my-backup.sql"
    echo ""
    echo "Prerequisites:"
    echo "  - Docker and docker-compose must be installed"
    echo "  - The .env file must exist in the current directory (.env)"
    echo "  - Database service must be defined in docker-compose.yml"
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    print_usage
    exit 0
fi

# Validate that the dump file exists
if [[ ! -f "$DUMP_FILE" ]]; then
    echo "Error: Dump file '$DUMP_FILE' does not exist!"
    echo "Please ensure the dump file is in the current directory."
    exit 1
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

echo "Database Restore Process"
echo "======================="
echo "Dump file: $DUMP_FILE"
echo "Environment: .env"
echo "Timestamp: $TIMESTAMP"
echo ""

# Get dump file info
DUMP_SIZE=$(stat -c%s "$DUMP_FILE" 2>/dev/null || stat -f%z "$DUMP_FILE" 2>/dev/null || echo "unknown")
LINE_COUNT=$(wc -l < "$DUMP_FILE")

echo "Dump file information:"
echo "  Size: $DUMP_SIZE bytes"
echo "  Lines: $LINE_COUNT"
echo ""

# Confirm with user
echo "⚠️  WARNING: This will DROP ALL DATA in the 'default' database!"
echo "Are you sure you want to continue? (y/N)"
read -r confirmation
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    echo "Restore cancelled by user."
    exit 0
fi

echo ""
echo "Starting database restore..."

# Step 1: Drop and recreate the database
echo "Step 1: Dropping and recreating database 'default'..."
echo 'Dropping database default...'
docker compose --env-file .env exec db psql -U twenty_user -d postgres -c "DROP DATABASE IF EXISTS \"default\";"
echo 'Creating database default...'
docker compose --env-file .env exec db psql -U twenty_user -d postgres -c "CREATE DATABASE \"default\";"

if [[ $? -ne 0 ]]; then
    echo "❌ Error: Failed to drop/create database!"
    exit 1
fi

echo "✅ Database 'default' dropped and recreated successfully."
echo ""

# Step 2: Restore from dump file
echo "Step 2: Restoring data from $DUMP_FILE..."
docker compose --env-file .env exec -T db psql -U twenty_user -d default < "$DUMP_FILE"

if [[ $? -ne 0 ]]; then
    echo "❌ Error: Failed to restore database from dump file!"
    echo "The database may be in an inconsistent state."
    exit 1
fi

echo "✅ Database restored successfully from $DUMP_FILE"
echo ""

# Step 3: Verify the restore
echo "Step 3: Verifying restore..."
TABLE_COUNT=$(docker compose --env-file .env exec -T db psql -U twenty_user -d default -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' \n\r')

echo "Tables found in restored database: $TABLE_COUNT"

if [[ "$TABLE_COUNT" -gt 0 ]]; then
    echo "✅ Restore verification successful - database contains $TABLE_COUNT tables."
else
    echo "⚠️  Warning: No tables found in restored database. This may indicate an issue."
fi

echo ""
echo "🎉 Database restore completed successfully!"
echo ""
echo "Summary:"
echo "  - Source: $DUMP_FILE ($DUMP_SIZE bytes, $LINE_COUNT lines)"
echo "  - Target: default database"
echo "  - Tables: $TABLE_COUNT"
echo "  - Completed: $(date)"
echo ""
echo "To create a new dump from the current database:"
echo "  docker compose --env-file .env exec -T db pg_dump -U twenty_user default > new_dump.sql"
