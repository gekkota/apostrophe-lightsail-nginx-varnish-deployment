#!/bin/bash
# update_install.sh - System update and installation

export DEBIAN_FRONTEND=noninteractive

# run_command and log_message should be defined functions,
# For example, if not already defined, you can add these:
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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

# Update package lists and upgrade installed packages
run_command "apt update && apt upgrade -y"

# --- Installing Node.js 22.x ---
if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node -v)
    if [[ "$NODE_VERSION" == v22* ]]; then
        log_message "Node.js $NODE_VERSION is already installed."
    else
        log_message "Detected Node.js version $NODE_VERSION. Upgrading to Node.js 22.x..."
        run_command "curl -sL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh"
        run_command "bash /tmp/nodesource_setup.sh"
        run_command "apt install nodejs -y"
    fi
else
    log_message "Node.js not found. Installing Node.js 22.x..."
    run_command "curl -sL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh"
    run_command "bash /tmp/nodesource_setup.sh"
    run_command "apt install nodejs -y"
fi

# --- Installing Nginx ---
if dpkg -l nginx 2>/dev/null | grep -q '^ii'; then
    log_message "Nginx is already installed."
else
    log_message "Installing Nginx..."
    run_command "apt install nginx -y"
fi

# --- Installing Varnish ---
if dpkg -l varnish 2>/dev/null | grep -q '^ii'; then
    log_message "Varnish is already installed."
else
    log_message "Installing Varnish..."
    run_command "apt install varnish -y"
fi

# TODO - remove this and move to the apos user: 
# Configure NPM for root and install PM2 globally
# log_message "Configuring NPM global path for root"
# run_command "mkdir -p /root/.npm-global"
# run_command "npm config set prefix '/root/.npm-global'"
# run_command "echo 'export PATH=/root/.npm-global/bin:\$PATH' >> /root/.profile"
# run_command "source /root/.profile"
# run_command "npm install -g pm2"