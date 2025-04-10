#!/bin/bash
# deploy_remote.sh - Script to deploy the entire Apostrophe CMS setup package
# to a remote server. This script copies the whole directory (including main.sh,
# config.sh, and the lib folder) to the remote server, makes main.sh executable,
# runs it with sudo, and then removes the .env file.
#
# It prompts for the server IP, username (default: ubuntu), and a PEM file.
# It also lets you choose from a list of available environment files located in a
# local "env" directory (e.g., env/entertainers.env). On the server, the env file 
# will be deployed as .env.
#
# Adjust the default PEM path as needed.

# === PEM & Username Setup ===
export CLICOLOR=1
export FORCE_COLOR=1

# Prompt for server username with default "ubuntu"
read -p "Enter the server username (default: ubuntu): " SERVER_USER
if [ -z "$SERVER_USER" ]; then
    SERVER_USER="ubuntu"
fi

# Prompt for PEM file number (if empty, use default)
read -p "Enter the PEM number (default PEM: ~/www/threekey/LightsailDefaultKey-eu-west-1.pem): " PEM_NO
# Remove any leading '#' if provided
PEM_NO=$(echo "$PEM_NO" | sed 's/^#//')
if [ -z "$PEM_NO" ]; then
    PEM_PATH="~/www/threekey/LightsailDefaultKey-eu-west-1.pem"
else
    PEM_PATH="~/www/threekey/LightsailDefaultKey-eu-west-${PEM_NO}.pem"
fi
# Expand tilde in PEM_PATH to full path
PEM_PATH=$(eval echo "$PEM_PATH")

# === Environment File Selection ===

# Let the user choose an environment file.
if [ -d "env" ]; then
    echo "Available environment files in ./env:"
    select ENV_FILE_CHOICE in env/*.env; do
        if [ -n "$ENV_FILE_CHOICE" ]; then
            echo "You selected: $ENV_FILE_CHOICE"
            break
        else
            echo "Invalid selection. Try again."
        fi
    done
elif [ -f ".env" ]; then
    ENV_FILE_CHOICE=".env"
    echo "Found .env file in current directory."
else
    echo "Error: No environment files found in 'env' directory or in current directory."
    exit 1
fi

# Optionally, copy the selected env file to .env locally for further processing.
cp "$ENV_FILE_CHOICE" .env

# === Determine the Server IP from .env Variables or Prompt ===

# First, check if the .env file contains BASE_URL.
SERVER_IP=""
if [ -f ".env" ]; then
    BASE_URL=$(grep '^BASE_URL=' .env | cut -d '=' -f2-)
    if [ -n "$BASE_URL" ]; then
        read -p "Found BASE_URL in .env: $BASE_URL. Do you want to use it as your SSH server address? (y/n): " use_base
        if [[ "$use_base" =~ ^[Yy]$ ]]; then
            # Remove the protocol (http:// or https://) from BASE_URL.
            SERVER_IP=$(echo "$BASE_URL" | sed 's~^https\?://~~')
        fi
    fi

    # If BASE_URL was not used, check if .env has a SERVER_IP entry.
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP_ENV=$(grep '^SERVER_IP=' .env | cut -d '=' -f2-)
        if [ -n "$SERVER_IP_ENV" ]; then
            read -p "Found SERVER_IP in .env: $SERVER_IP_ENV. Do you want to use it as your SSH server address? (y/n): " use_server_ip
            if [[ "$use_server_ip" =~ ^[Yy]$ ]]; then
                SERVER_IP="$SERVER_IP_ENV"
            fi
        fi
    fi
fi

# If no value was determined from the .env file, prompt the user.
if [ -z "$SERVER_IP" ]; then
    read -p "Enter the server IP address: " SERVER_IP
fi

echo "Using server IP: $SERVER_IP"

# === Continue with the Remainder of the Script ===

# Check that main.sh exists locally (the new entry point)
if [ ! -f "main.sh" ]; then
    echo "Error: main.sh not found in the current directory."
    exit 1
fi

# Define the remote destination directory name.
DEST_DIR="apostrophe-setup"

echo "Copying setup files to ${SERVER_USER}@${SERVER_IP}:~/${DEST_DIR}..."
rsync -avz -e "ssh -i $PEM_PATH" --exclude '/deploy.sh' --exclude 'env/' --exclude '/.env' --exclude 'templates/varnish.vcl' ./ "${SERVER_USER}@${SERVER_IP}:~/${DEST_DIR}/"

# Make a temp copy of the varnish file to copy to the remote server but replace $APP_NAME$ with the actual app name.
# Get PROJECT_SHORTNAME from .env file (which we copied from our chosen file)
APP_NAME=$(grep '^PROJECT_SHORTNAME=' .env | cut -d '=' -f2)
if [ -z "$APP_NAME" ]; then
    echo "Error: APP_NAME not found in .env file."
    exit 1
fi

# Function to escape characters for sed replacement.
escape_for_sed() {
    echo "$1" | sed -e 's/[\/&]/\\&/g'
}

# Create a temporary varnish file with the app name replaced.
TEMP_VARNISH_FILE="templates/varnish.vcl.tmp"
if [ -f "templates/varnish.vcl" ]; then
    APP_NAME_ESCAPED=$(escape_for_sed "$APP_NAME")
    sed "s|\$APP_NAME\$|$APP_NAME_ESCAPED|g" templates/varnish.vcl > "$TEMP_VARNISH_FILE"
    # Copy the temporary varnish file to the remote server.
    echo "Copying varnish template to ${SERVER_USER}@${SERVER_IP}:~/${DEST_DIR}/templates/varnish.vcl..."
    scp -i "$PEM_PATH" "$TEMP_VARNISH_FILE" "${SERVER_USER}@${SERVER_IP}:~/${DEST_DIR}/templates/varnish.vcl"
    # Remove the temporary varnish file.
    rm "$TEMP_VARNISH_FILE"
else
    echo "Warning: templates/varnish.vcl not found locally. Skipping copy."
fi

# Sync the chosen environment file to the remote server.
echo "Copying environment file ($ENV_FILE_CHOICE) to ${SERVER_USER}@${SERVER_IP}:/opt/env/apostrophe.env"
# Create the directory on the remote server using sudo
ssh -i "$PEM_PATH" "${SERVER_USER}@${SERVER_IP}" "sudo mkdir -p /opt/env/ && sudo chown ${SERVER_USER}:${SERVER_USER} /opt/env"
# Copy the environment file, renaming it to .env on the remote server.
scp -i "$PEM_PATH" "$ENV_FILE_CHOICE" "${SERVER_USER}@${SERVER_IP}:/opt/env/apostrophe.env"

echo "Setting main.sh executable and running it on ${SERVER_IP}..."
# Remotely make main.sh executable and run it with sudo.
ssh -i "$PEM_PATH" "${SERVER_USER}@${SERVER_IP}" "chmod +x ~/${DEST_DIR}/main.sh && sudo bash ~/${DEST_DIR}/main.sh"

# After main.sh runs, remove the .env file from the remote server if it was copied.
if [ -f "$ENV_FILE_CHOICE" ]; then
    echo "Cleaning up .env file on remote server..."
    ssh -i "$PEM_PATH" "${SERVER_USER}@${SERVER_IP}" "rm -f ~/${DEST_DIR}/.env"
fi

echo "Remote configuration completed."