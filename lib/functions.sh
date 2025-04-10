#!/bin/bash
# functions.sh - Common functions

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

run_command() {
    log_message "EXECUTING: $1"
    eval "$1"
    local status=$?
    if [ $status -eq 0 ]; then
        log_message "SUCCESS: Command executed successfully"
    else
        log_message "ERROR: Command failed with status $status"
    fi
    return $status
}

# Function to escape characters for sed replacement.
escape_for_sed() {
    echo "$1" | sed -e 's/[\/&]/\\&/g'
}