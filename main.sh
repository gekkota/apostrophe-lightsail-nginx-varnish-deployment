#!/bin/bash
# main.sh - Main driver for Apostrophe CMS setup

# Ensure the script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi

cd "$(dirname "$0")" || {
  echo "Failed to change directory to $(dirname "$0")"
  exit 1
}


# Load configuration variables
source ./lib/config.sh

# Load common functions and log setup
source ./lib/functions.sh

log_message "==== APOSTROPHE CMS SETUP SCRIPT STARTED ===="

# Run system update and install Node.js, nginx, varnish, PM2, etc.
source ./lib/update_install.sh

# Configure Varnish (including systemd override)
source ./lib/varnish.sh

# Configure nginx to proxy requests to Varnish
source ./lib/nginx.sh

# Create app user and set up necessary directories/SSH keys
source ./lib/app_user.sh

# Create the deployment script that your app user will run
source ./lib/deploy_script.sh

su - "$APP_USER" -c "$DEPLOY_SCRIPTS_DIR/deploy.sh"

source ./lib/post_deploy.sh

# Perform cleanup tasks
source ./lib/cleanup.sh

log_message "==== APOSTROPHE CMS SETUP SCRIPT COMPLETED ===="
echo "Setup completed successfully!"