#!/bin/bash
# nginx.sh - Configure nginx to proxy to Varnish

# Define your helper functions if not already defined
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

log_message "Configuring nginx to proxy requests to Varnish"

# Define the desired configuration for nginx
DESIRED_NGINX_CONF=$(cat <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:81;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
)

NGINX_CONF_FILE="/etc/nginx/sites-available/varnish_proxy"

# Check if the file exists and if its content matches the desired configuration
if [ ! -f "$NGINX_CONF_FILE" ] || ! diff -q "$NGINX_CONF_FILE" <(echo "$DESIRED_NGINX_CONF") >/dev/null 2>&1; then
    log_message "Writing desired nginx configuration to $NGINX_CONF_FILE"
    echo "$DESIRED_NGINX_CONF" > "$NGINX_CONF_FILE"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to write $NGINX_CONF_FILE"
        exit 1
    fi
else
    log_message "$NGINX_CONF_FILE already matches desired configuration."
fi

# Ensure the correct symlink exists in sites-enabled
NGINX_ENABLED_LINK="/etc/nginx/sites-enabled/varnish_proxy"
if [ ! -L "$NGINX_ENABLED_LINK" ] || [ "$(readlink "$NGINX_ENABLED_LINK")" != "$NGINX_CONF_FILE" ]; then
    log_message "Creating symlink from $NGINX_CONF_FILE to $NGINX_ENABLED_LINK"
    ln -sf "$NGINX_CONF_FILE" "$NGINX_ENABLED_LINK"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to create symlink $NGINX_ENABLED_LINK"
        exit 1
    fi
else
    log_message "Symlink $NGINX_ENABLED_LINK already exists."
fi

# Remove the default configuration if it exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    log_message "Removing default nginx configuration from /etc/nginx/sites-enabled/default"
    rm -f /etc/nginx/sites-enabled/default
fi

# Test the nginx configuration and reload if the test passes
run_command "nginx -t"
if [ $? -eq 0 ]; then
    run_command "systemctl reload nginx"
else
    log_message "ERROR: Nginx configuration test failed. Please check your configuration."
    exit 1
fi