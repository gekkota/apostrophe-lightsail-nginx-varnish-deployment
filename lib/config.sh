#!/bin/bash
# config.sh - Global configuration variables

REPO_URL="git@bitbucket.org:lev_lev/entertainers.git"
BRANCH="production"
PM2_INSTANCES=1
APP_USER="apos"
APP_DIR="/var/www/apostrophe"
ENV_DIR="/opt/env"
ENV_FILE="$ENV_DIR/apostrophe.env"
DEPLOY_SCRIPTS_DIR="/home/apos/deploy-scripts"
LOG_FILE="/var/log/apostrophe_setup.log"

# Load any extra environment variables if needed
set -o allexport
# set the source to the end file from the variables
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
set +o allexport