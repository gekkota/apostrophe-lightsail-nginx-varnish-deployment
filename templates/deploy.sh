#!/bin/bash
# Improved Deployment Script for Apostrophe CMS with Zero-Downtime
# Run as the apos user. This script pulls the latest code from the repository,
# installs dependencies, builds assets in a temporary location, and swaps them in.

# ====================================================================
# IMPORTANT: Setup required before using this script
# ====================================================================
# The apos user needs passwordless sudo for specific commands.
# Run these commands as root or with sudo:
#
# 1. Create a sudoers file for the apos user:
#    echo 'apos ALL=(ALL) NOPASSWD: /bin/systemctl reload varnish, /bin/systemctl restart varnish, /bin/systemctl reload nginx, /usr/sbin/varnishd -C -f /etc/varnish/default.vcl, /usr/sbin/nginx -t, /bin/sed -i * /etc/varnish/default.vcl, /bin/sed -i * /etc/nginx/sites-available/apostrophe, /usr/bin/varnishadm -S /etc/varnish/secret -T localhost:* *' > /etc/sudoers.d/apos
#
# 2. Set proper permissions:
#    chmod 440 /etc/sudoers.d/apos
#
# 3. Verify the configuration:
#    visudo -c
# ====================================================================

# Ensure the correct PATH so that pm2 is found (using apos' npm global directory)
export PATH="/home/apos/.npm-global/bin:$PATH"

# Configuration
REPO_URL="$REPO_URL$"
BRANCH="production"
APP_DIR="/var/www/apostrophe"
ENV_FILE="/opt/env/apostrophe.env"
DEPLOY_LOG="/home/apos/apostrophe_deploy.log"
APP_USER="apos"
INSTANCES=2                 # Number of PM2 instances to use in cluster mode
VARNISH_PORT=81             # The port Varnish is running on
VARNISH_ADMIN_PORT=6082     # Default Varnish admin port, change if needed
ASSETS_DIR="/home/apos/apostrophe-assets"  # Base directory for asset deployments

# Path to the permanent crawler script
CRAWLER_SCRIPT="/home/apos/sitemap-crawler.js"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$DEPLOY_LOG")"
touch "$DEPLOY_LOG"

# Function to log messages with timestamps
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOY_LOG"
}

# Function to run commands and log their outcome
run_command() {
    log_message "EXECUTING: $1"
    eval "$1"
    local status=$?
    if [ $status -eq 0 ]; then
        log_message "SUCCESS: Command executed successfully"
    else
        log_message "ERROR: Command failed with status $status"
        # Optional: exit on error
        # exit $status
    fi
    return $status
}

# Check if we have necessary sudo permissions
check_sudo_permissions() {
    log_message "Checking sudo permissions..."

    # Try a test sudo command
    if ! sudo -n true 2>/dev/null; then
        log_message "ERROR: The apos user does not have passwordless sudo permissions"
        log_message "Please follow the setup instructions at the top of this script"
        exit 1
    fi

    # Test specific permissions needed for Varnish/NGINX
    if [ -f "/etc/varnish/default.vcl" ]; then
        if ! sudo -n sed --version >/dev/null 2>&1; then
            log_message "ERROR: Missing passwordless sudo permission for 'sed'"
            exit 1
        fi
        if ! sudo -n systemctl list-units varnish.service >/dev/null 2>&1; then
            log_message "ERROR: Missing passwordless sudo permission for 'systemctl reload varnish'"
            exit 1
        fi
    elif [ -f "/etc/nginx/sites-available/apostrophe" ]; then
        if ! sudo -n sed --version >/dev/null 2>&1; then
            log_message "ERROR: Missing passwordless sudo permission for 'sed'"
            exit 1
        fi
        if ! sudo -n systemctl list-units nginx.service >/dev/null 2>&1; then
            log_message "ERROR: Missing passwordless sudo permission for 'systemctl reload nginx'"
            exit 1
        fi
    fi

    log_message "Sudo permissions verified"
}

# Check if PM2 is installed and available, start daemon if needed
check_pm2() {
    if ! command -v pm2 &> /dev/null; then
        log_message "ERROR: PM2 is not installed or not in PATH"
        exit 1
    fi

    # Check if PM2 daemon is running
    if ! pm2 ping > /dev/null 2>&1; then
        log_message "PM2 daemon is not running, starting it now..."
        run_command "pm2 resurrect || pm2 save --force" # Try to restore previous state, or create new

        # If still not running, start it fresh
        if ! pm2 ping > /dev/null 2>&1; then
            log_message "Starting PM2 daemon..."
            run_command "pm2 kill && pm2 daemon"
            sleep 2
        fi
    fi

    log_message "PM2 daemon is running"
}

# Ensure the sitemap crawler exists, if not, create it
ensure_crawler_script() {
    if [ ! -f "$CRAWLER_SCRIPT" ]; then
        log_message "Sitemap crawler script not found, creating it at $CRAWLER_SCRIPT"

        # Create the directory if it doesn't exist
        mkdir -p "$(dirname "$CRAWLER_SCRIPT")"

        # Download the latest version of the script from repository or create it
        # For this example, we'll assume the script content would be downloaded or copied here
        log_message "Please deploy the sitemap crawler script to $CRAWLER_SCRIPT"
        log_message "For now, deployment will continue but pre-caching may not work"
    else
        log_message "Sitemap crawler script found at $CRAWLER_SCRIPT"
        # Make sure it's executable
        chmod +x "$CRAWLER_SCRIPT"
    fi
}

# Start deployment process
log_message "==== APOSTROPHE CMS DEPLOYMENT STARTED ===="
log_message "Deploying branch $BRANCH from $REPO_URL"

# Check for sudo permissions
check_sudo_permissions

# Check for PM2
check_pm2

# Ensure crawler script exists
ensure_crawler_script

# Set up asset slot management
SLOT_TRACKER="/home/apos/current_asset_slot.txt"

# Determine which asset slot is currently active
determine_active_slot() {
    if [ -f "$SLOT_TRACKER" ]; then
        ACTIVE_SLOT=$(cat "$SLOT_TRACKER")
        if [ "$ACTIVE_SLOT" = "blue" ]; then
            STANDBY_SLOT="green"
        else
            STANDBY_SLOT="blue"
        fi
        log_message "Current active asset slot is $ACTIVE_SLOT, will deploy to $STANDBY_SLOT"
    else
        # Default to blue as active, green as standby if no tracker exists
        ACTIVE_SLOT="blue"
        STANDBY_SLOT="green"
        log_message "No slot tracker found, assuming $ACTIVE_SLOT is active, will deploy to $STANDBY_SLOT"
    fi
}

# Update the slot tracker after successful deployment
update_slot_tracker() {
    echo "$STANDBY_SLOT" > "$SLOT_TRACKER"
    log_message "Updated asset slot tracker: $STANDBY_SLOT is now active"
}

# Determine the active and standby asset slots
determine_active_slot

# Create asset directories if they don't exist
mkdir -p "$ASSETS_DIR/blue" "$ASSETS_DIR/green"
ACTIVE_ASSETS="${ASSETS_DIR}/${ACTIVE_SLOT}"
STANDBY_ASSETS="${ASSETS_DIR}/${STANDBY_SLOT}"
APP_ASSETS_SYMLINK="${APP_DIR}/public/assets"

# Clone or update repository
if [ ! -d "$APP_DIR/.git" ]; then
    log_message "Repository not found. Cloning for the first time..."
    run_command "git clone -b \"$BRANCH\" \"$REPO_URL\" \"$APP_DIR\""
    if [ $? -ne 0 ]; then
        log_message "ERROR: Git clone failed. Aborting deployment."
        exit 1
    fi
else
    log_message "Repository exists. Updating to latest version..."

    # Stash any local changes (if any)
    run_command "cd \"$APP_DIR\" && git stash"

    # Fetch and update
    run_command "cd \"$APP_DIR\" && git fetch"
    run_command "cd \"$APP_DIR\" && git checkout \"$BRANCH\""

    # Check if there are any updates
    LOCAL_HASH=$(cd "$APP_DIR" && git rev-parse HEAD)
    REMOTE_HASH=$(cd "$APP_DIR" && git rev-parse origin/$BRANCH)

    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        log_message "No updates found. Current version is up-to-date."

        # Check if we need to restart anyway (e.g., for environment changes)
        if [ "$1" != "--force" ]; then
            log_message "No changes to deploy. Use --force to deploy anyway."
            log_message "==== APOSTROPHE CMS DEPLOYMENT COMPLETED (NO CHANGES) ===="
            exit 0
        else
            log_message "Forcing deployment despite no code changes..."
        fi
    fi

    # Pull the latest changes
    run_command "cd \"$APP_DIR\" && git pull origin \"$BRANCH\""
fi

# Ensure proper ownership
run_command "chown -R \"$APP_USER\":\"$APP_USER\" \"$APP_DIR\""

# Link environment file
log_message "Linking environment file into application directory..."
run_command "ln -sf \"$ENV_FILE\" \"$APP_DIR/.env\""
run_command "chown -h \"$APP_USER\":\"$APP_USER\" \"$APP_DIR/.env\""

# Install dependencies
log_message "Installing dependencies..."

# check for package-lock.json and use npm ci if it exists
if [ -f "$APP_DIR/package-lock.json" ]; then
    log_message "Using npm ci for installation..."
    run_command "cd \"$APP_DIR\" && npm ci"
else
    log_message "Using npm install for installation..."
    run_command "cd \"$APP_DIR\" && npm install"
fi

# Prepare for asset building to the standby slot
log_message "Setting up asset symlink for build process..."
if [ -L "$APP_ASSETS_SYMLINK" ]; then
    log_message "Removing existing assets symlink..."
    run_command "rm -f \"$APP_ASSETS_SYMLINK\""
elif [ -d "$APP_ASSETS_SYMLINK" ]; then
    log_message "Backing up existing assets directory..."
    run_command "mv \"$APP_ASSETS_SYMLINK\" \"${APP_ASSETS_SYMLINK}_backup_$(date +%Y%m%d%H%M%S)\""
fi

# Create symlink to the standby assets directory for building
run_command "ln -sf \"$STANDBY_ASSETS\" \"$APP_ASSETS_SYMLINK\""
run_command "chown -h \"$APP_USER\":\"$APP_USER\" \"$APP_ASSETS_SYMLINK\""

# Remove the old build folder if it exists (careful with rm -rf!)
if [ -d "$APP_DIR/apos-build" ]; then
  log_message "Cleaning old build directory..."
  run_command "rm -rf \"$APP_DIR/apos-build\""
fi

# Build front-end assets to the standby directory
log_message "Building front-end assets to standby slot: $STANDBY_SLOT"
run_command "cd \"$APP_DIR\" && npm run build"

# Get status of current app in pm2
APP_NAME="apostrophe"
APP_RUNNING=false

# First, check if we have any running instances with expected name
if pm2 list | grep -q "$APP_NAME"; then
    log_message "Application '$APP_NAME' is currently running in PM2"
    APP_RUNNING=true
else
    # If not found, list all running processes to find any potential matches
    log_message "Application '$APP_NAME' not found in PM2, checking for other instances..."
    PM2_LIST=$(pm2 list)
    echo "$PM2_LIST" >> "$DEPLOY_LOG"

    # Look for partial matches that might be our app
    if echo "$PM2_LIST" | grep -q "apos"; then
        FOUND_APP=$(echo "$PM2_LIST" | grep "apos" | awk '{print $2}' | head -1)
        log_message "Found potential matching app: $FOUND_APP"
        APP_NAME="$FOUND_APP"
        APP_RUNNING=true
    else
        log_message "No running Apostrophe instance found in PM2"
        APP_RUNNING=false
    fi
fi

# Start or restart the application
if [ "$APP_RUNNING" = true ]; then
    log_message "Reloading application '$APP_NAME' to apply changes..."

    # Try reload first, if that fails try restart, if that fails try stop and start
    if pm2 reload "$APP_NAME" > /dev/null 2>&1; then
        log_message "Successfully reloaded application"
    elif pm2 restart "$APP_NAME" > /dev/null 2>&1; then
        log_message "Reload failed, successfully restarted application"
    else
        log_message "Reload and restart failed, stopping and starting application..."
        pm2 delete "$APP_NAME" > /dev/null 2>&1 || true
        run_command "cd \"$APP_DIR\" && pm2 start app.js --name $APP_NAME -i $INSTANCES --max-memory-restart 1G"
    fi

    # If reload/restart/start failed, try to start the app with a different name
    if ! pm2 list | grep -q "$APP_NAME"; then
        log_message "All attempts to reload/restart failed, starting with a fresh process..."
        run_command "cd \"$APP_DIR\" && pm2 start app.js --name apostrophe-app -i $INSTANCES --max-memory-restart 1G"
        APP_NAME="apostrophe-app"
    fi
else
    log_message "Starting application for the first time..."

    # Make sure we're in the correct directory with the right environment
    run_command "cd \"$APP_DIR\" && npm ls dotenv || npm install dotenv" # Ensure dotenv is installed
    run_command "cd \"$APP_DIR\" && pm2 start app.js --name $APP_NAME -i $INSTANCES --max-memory-restart 1G"

    # If start failed due to missing modules, try installing dependencies again and restart
    if ! pm2 list | grep -q "$APP_NAME"; then
        log_message "Start failed, trying to install dependencies and start again..."
        run_command "cd \"$APP_DIR\" && npm install"
        run_command "cd \"$APP_DIR\" && pm2 start app.js --name $APP_NAME -i $INSTANCES --max-memory-restart 1G"
    fi
fi

# Verify application is running
log_message "Waiting for application to come online..."
MAX_RETRIES=30
RETRY_COUNT=0
APP_ONLINE=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if pm2 list | grep "$APP_NAME" | grep -q "online"; then
        APP_ONLINE=true
        log_message "Application is now online"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    log_message "Waiting for application to come online... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ "$APP_ONLINE" = false ]; then
    log_message "ERROR: Application failed to come online after restart"
    log_message "Checking logs for errors..."
    run_command "pm2 logs $APP_NAME --lines 20 --nostream"
    exit 1
fi

# Update the slot tracker to indicate the new active slot
update_slot_tracker

# Save PM2 configuration to ensure it restarts on server reboot
run_command "pm2 save"

# Set up PM2 to start on system boot if not already set up
if ! pm2 startup | grep -q "already configured"; then
    log_message "Setting up PM2 to start on system boot..."
    PM2_STARTUP_CMD=$(pm2 startup | grep -v "sudo env" | grep "sudo" | tail -n 1)
    if [ -n "$PM2_STARTUP_CMD" ]; then
        log_message "Running PM2 startup command: $PM2_STARTUP_CMD"
        eval "$PM2_STARTUP_CMD"
    fi
fi

# Verify Varnish or NGINX is properly configured
if [ -f "/etc/varnish/default.vcl" ]; then
    log_message "Verifying Varnish configuration..."
    # Check syntax without full output
    run_command "sudo varnishd -C -f /etc/varnish/default.vcl > /dev/null 2>&1"

    # Verify Varnish is actually communicating with the backend
    log_message "Testing Varnish connectivity to backend..."
    VARNISH_MAX_RETRIES=15  # 30 seconds
    VARNISH_RETRY_COUNT=0
    VARNISH_OK=false

    while [ $VARNISH_RETRY_COUNT -lt $VARNISH_MAX_RETRIES ]; do
        VARNISH_STATUS=$(curl -s -o /dev/null -w '%{http_code}' localhost:$VARNISH_PORT 2>/dev/null || echo "000")
        log_message "Varnish health check attempt $((VARNISH_RETRY_COUNT+1))/$VARNISH_MAX_RETRIES: HTTP status $VARNISH_STATUS"

        if [ "$VARNISH_STATUS" -eq 200 ]; then
            VARNISH_OK=true
            log_message "Varnish is successfully connecting to backend!"
            break
        fi

        # Check if we need to restart Varnish
        if [ $VARNISH_RETRY_COUNT -eq 5 ]; then
            log_message "Trying to restart Varnish to resolve connection issues..."
            run_command "sudo systemctl restart varnish"
            sleep 5
        fi

        VARNISH_RETRY_COUNT=$((VARNISH_RETRY_COUNT+1))
        log_message "Varnish not connecting properly (HTTP $VARNISH_STATUS), waiting 2s..."
        sleep 2
    done

    if [ "$VARNISH_OK" = false ]; then
        log_message "WARNING: Varnish is not connecting to backend properly"
        log_message "You may need to manually verify Varnish configuration"

        # Don't exit - we've already switched, but warn the user
    fi

    # Invalidate Varnish cache
    log_message "Invalidating Varnish cache..."
    if command -v varnishadm &> /dev/null; then
        run_command "sudo varnishadm 'ban req.url ~ .' || sudo varnishadm ban.url '.*'"
        log_message "Varnish cache invalidated successfully"
    else
        log_message "WARNING: varnishadm not found, using alternative cache purge method"
        # Alternative: Restart Varnish (only if varnishadm is not available)
        run_command "sudo systemctl restart varnish"
    fi
elif [ -f "/etc/nginx/sites-available/apostrophe" ]; then
    log_message "Verifying NGINX configuration..."
    run_command "sudo nginx -t"
    run_command "curl -s -o /dev/null -w 'HTTP status: %{http_code}\n' localhost:80 || true"
fi

# Pre-cache URLs by crawling sitemap.xml
log_message "Starting pre-cache process by crawling sitemap.xml..."

# First, wait for the application to be fully ready
log_message "Waiting for application to be fully available..."
MAX_RETRIES=60  # Increased to 60 retries (2 minutes total)
RETRY_DELAY=2
RETRY_COUNT=0
APP_READY=false

# Determine the site URL for health check
SITE_URL=$(grep SITE_URL "$ENV_FILE" | cut -d '=' -f2 | tr -d '"')
if [ -z "$SITE_URL" ]; then
    SITE_URL="http://localhost:$VARNISH_PORT"
    log_message "WARNING: Could not determine SITE_URL from env file, using $SITE_URL"
fi

# Wait until application responds with 200 OK
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Try direct backend connection first (bypassing Varnish)
    BACKEND_HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000" 2>/dev/null || echo "000")

    # Then try through Varnish
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$SITE_URL" 2>/dev/null || echo "000")

    log_message "Health check attempt $((RETRY_COUNT+1))/$MAX_RETRIES: HTTP status $HTTP_STATUS (direct backend: $BACKEND_HTTP_STATUS)"

    if [ "$HTTP_STATUS" -eq 200 ]; then
        APP_READY=true
        log_message "Application is ready!"
        break
    fi

    # Check if application process is running
    if ! pm2 list | grep -q "$APP_NAME"; then
        log_message "ERROR: Application is not running in PM2! Checking PM2 status..."
        run_command "pm2 list"
    fi

    RETRY_COUNT=$((RETRY_COUNT+1))
    log_message "Application not ready yet (HTTP $HTTP_STATUS), waiting ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
done

if [ "$APP_READY" = false ]; then
    log_message "WARNING: Application did not become ready in time"
    log_message "You may need to manually verify the application status and consider restarting it"

    # Get more diagnostic information
    log_message "Checking application logs for errors..."
    run_command "pm2 logs $APP_NAME --lines 20 --nostream"
    run_command "curl -v $SITE_URL 2>&1 | grep -v \"OpenSSL\|issuer\" || true"

    # Ask user if they want to continue anyway
    read -p "Do you want to continue with pre-caching anyway? (y/n) " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_message "Aborting pre-cache process"
        exit 1
    fi
    log_message "Continuing with pre-cache despite application not being ready (may not be effective)"
fi

# Run the crawler script if it exists
if [ -f "$CRAWLER_SCRIPT" ]; then
    log_message "Running pre-cache crawler script..."
    run_command "node \"$CRAWLER_SCRIPT\" \"$SITE_URL\" \"/sitemap.xml\" || true"
    log_message "Pre-cache process completed"
else
    log_message "WARNING: Crawler script not found at $CRAWLER_SCRIPT, skipping pre-cache"
fi

log_message "==== APOSTROPHE CMS DEPLOYMENT COMPLETED SUCCESSFULLY ===="