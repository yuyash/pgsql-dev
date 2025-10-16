#!/bin/bash
set -e

# Logging function for consistent output
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Validate required environment variables
if [ -z "$PGDATA" ]; then
    error_exit "PGDATA environment variable is not set"
fi

log "PostgreSQL Docker Entrypoint Script"
log "PGDATA: $PGDATA"

# Check if database is initialized
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    log "Database not initialized. Starting initialization process..."
    
    # Ensure PGDATA directory exists and has correct permissions
    if [ ! -d "$PGDATA" ]; then
        log "Creating PGDATA directory: $PGDATA"
        mkdir -p "$PGDATA" || error_exit "Failed to create PGDATA directory"
    fi
    
    # Verify directory permissions
    if [ ! -w "$PGDATA" ]; then
        error_exit "PGDATA directory is not writable: $PGDATA"
    fi
    
    # Initialize database cluster
    log "Running initdb to initialize database cluster..."
    if ! initdb -D "$PGDATA" \
        --encoding=UTF8 \
        --locale=en_US.UTF-8 \
        --username=postgres \
        --pwfile=<(echo "${POSTGRES_PASSWORD:-postgres}"); then
        error_exit "initdb failed"
    fi
    
    log "Database initialized successfully"
    
    # Copy configuration files from mounted volume to PGDATA if they exist
    if [ -f /etc/postgresql/postgresql.conf ]; then
        log "Copying postgresql.conf from /etc/postgresql to $PGDATA"
        if ! cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"; then
            error_exit "Failed to copy postgresql.conf"
        fi
        log "postgresql.conf copied successfully"
    else
        log "No custom postgresql.conf found at /etc/postgresql, using defaults"
    fi
    
    if [ -f /etc/postgresql/pg_hba.conf ]; then
        log "Copying pg_hba.conf from /etc/postgresql to $PGDATA"
        if ! cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"; then
            error_exit "Failed to copy pg_hba.conf"
        fi
        log "pg_hba.conf copied successfully"
    else
        log "No custom pg_hba.conf found at /etc/postgresql, using defaults"
    fi
    
    log "First-time initialization completed successfully"
else
    log "PostgreSQL database already initialized (found $PGDATA/PG_VERSION)"
    
    # Update configuration files if they exist in mounted volume
    if [ -f /etc/postgresql/postgresql.conf ]; then
        log "Updating postgresql.conf from /etc/postgresql"
        if ! cp /etc/postgresql/postgresql.conf "$PGDATA/postgresql.conf"; then
            log "WARNING: Failed to update postgresql.conf, continuing with existing configuration"
        else
            log "postgresql.conf updated successfully"
        fi
    fi
    
    if [ -f /etc/postgresql/pg_hba.conf ]; then
        log "Updating pg_hba.conf from /etc/postgresql"
        if ! cp /etc/postgresql/pg_hba.conf "$PGDATA/pg_hba.conf"; then
            log "WARNING: Failed to update pg_hba.conf, continuing with existing configuration"
        else
            log "pg_hba.conf updated successfully"
        fi
    fi
fi

# Verify PostgreSQL binaries are available
if ! command -v postgres &> /dev/null; then
    error_exit "postgres binary not found in PATH"
fi

if ! command -v pg_ctl &> /dev/null; then
    error_exit "pg_ctl binary not found in PATH"
fi

# Start PostgreSQL using pg_ctl
log "Starting PostgreSQL server using pg_ctl..."

# Use pg_ctl to start PostgreSQL in foreground mode
# The -w flag waits for startup to complete
# The -l flag specifies the log file location
if ! pg_ctl -D "$PGDATA" -w -l "$PGDATA/postgresql.log" start; then
    error_exit "Failed to start PostgreSQL with pg_ctl"
fi

log "PostgreSQL started successfully"
log "Server is ready to accept connections"

# Keep the container running by tailing the log file
# This ensures the container doesn't exit and allows log viewing
exec tail -f "$PGDATA/postgresql.log"
