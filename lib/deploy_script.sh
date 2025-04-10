#!/bin/bash
# deploy_script.sh - Create and configure the deployment script

log_message "Writing deployment script"
run_command "mkdir -p \"$DEPLOY_SCRIPTS_DIR\""
run_command "chown -R \"$APP_USER\":\"$APP_USER\" \"$DEPLOY_SCRIPTS_DIR\""

# Copy the deploy.sh script from templates/deploy.sh to the deployment directory
# run_command "cp ./templates/deploy.sh \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""
CUSTOM_DEPLOY_SCRIPT="$(dirname "$0")/templates/deploy.sh"
if [ ! -f "$CUSTOM_DEPLOY_SCRIPT" ]; then
    log_message "Error: Deploy script not found at $CUSTOM_DEPLOY_SCRIPT"
    exit 1
fi

# Escape the REPO_URL to prevent issues with sed (in case it contains slashes or ampersands).
REPO_URL_ESCAPED=$(escape_for_sed "$REPO_URL")

log_message "Copying custom deployment script from $CUSTOM_DEPLOY_SCRIPT to $DEPLOY_SCRIPTS_DIR/deploy.sh with REPO_URL replaced with $REPO_URL"
# Use sed to substitute the placeholder with the actual REPO_URL and write it to the deploy destination.
sed "s|\"\$REPO_URL\$\"|\"$REPO_URL_ESCAPED\"|g" "$CUSTOM_DEPLOY_SCRIPT" > "$DEPLOY_SCRIPTS_DIR/deploy.sh"

run_command "chmod +x \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""
run_command "chown \"$APP_USER\":\"$APP_USER\" \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""

# TODO: Configure the deployment script with custom variables
# log_message "Configuring the deployment script with custom variables"
# run_command "sed -i \"s|__REPO_URL__|$REPO_URL|g\" \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""
# run_command "sed -i \"s|__BRANCH__|$BRANCH|g\" \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""
# run_command "sed -i \"s|__PM2_INSTANCES__|$PM2_INSTANCES|g\" \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""
# run_command "sed -i \"s|__ENV_FILE__|$ENV_FILE|g\" \"$DEPLOY_SCRIPTS_DIR/deploy.sh\""