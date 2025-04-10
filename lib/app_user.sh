#!/bin/bash
# app_user.sh - Create app user and configure SSH for deployment

log_message "Creating application user and directories"
run_command "adduser --disabled-password --gecos \"\" --home /home/$APP_USER \"$APP_USER\""
run_command "mkdir -p /home/$APP_USER"
run_command "chown -R \"$APP_USER\":\"$APP_USER\" /home/$APP_USER"
run_command "mkdir -p \"$APP_DIR\""
run_command "chown -R \"$APP_USER\":\"$APP_USER\" \"$APP_DIR\""

# Setup NPM global for the app user
log_message "Setting up npm global directory for $APP_USER"
run_command "sudo -u \"$APP_USER\" mkdir -p /home/$APP_USER/.npm-global"
run_command "sudo -u \"$APP_USER\" npm config set prefix '/home/$APP_USER/.npm-global'"
run_command "touch /home/$APP_USER/.bashrc"
run_command "chown $APP_USER:$APP_USER /home/$APP_USER/.bashrc"
run_command "echo 'export PATH=/home/$APP_USER/.npm-global/bin:\$PATH' | sudo tee -a /home/$APP_USER/.profile"
run_command "echo 'export PATH=/home/$APP_USER/.npm-global/bin:\$PATH' | sudo tee -a /home/$APP_USER/.bashrc"
run_command "mkdir -p /home/$APP_USER/.npm"
run_command "chown -R \"$APP_USER\":\"$APP_USER\" /home/$APP_USER/.npm"

# Setup SSH keys (copying root authorized_keys if available)
log_message "Setting up SSH authorized_keys for $APP_USER"
run_command "mkdir -p /home/$APP_USER/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    run_command "cp /root/.ssh/authorized_keys /home/$APP_USER/.ssh/"
fi
run_command "chown -R \"$APP_USER\":\"$APP_USER\" /home/$APP_USER/.ssh"
run_command "chmod 700 /home/$APP_USER/.ssh"
run_command "chmod 600 /home/$APP_USER/.ssh/authorized_keys"

# run the apos_user_sudo.sh script to set up passwordless sudo for the app user
log_message "Setting up passwordless sudo for $APP_USER"
run_command "bash -c 'bash -s' < ./lib/apos_user_sudo.sh"


#############################
# SETUP SSH CONFIG FOR APOS #
#############################
log_message "SECTION: Setting up SSH config for $APP_USER"
cat <<'EOF' > /home/apos/.ssh/config
Host bitbucket.org
    IdentityFile ~/.ssh/bitbucket_deploy_key
    StrictHostKeyChecking no
EOF
run_command "chown $APP_USER:$APP_USER /home/apos/.ssh/config"
run_command "chmod 600 /home/apos/.ssh/config"

#############################
# SETUP BITBUCKET DEPLOY KEY#
#############################
log_message "SECTION: Setting up Bitbucket deploy key for $APP_USER"
if [ ! -f /home/apos/.ssh/bitbucket_deploy_key ]; then
    log_message "Generating new SSH deploy key for Bitbucket"
    run_command "sudo -u \"$APP_USER\" ssh-keygen -t ed25519 -C \"aws-lightsail-deploy\" -f /home/apos/.ssh/bitbucket_deploy_key -N \"\""
    log_message "Bitbucket deploy key generated."
    log_message "The public key is saved at /home/apos/.ssh/bitbucket_deploy_key.pub."
    log_message "Please add its contents to your Bitbucket repository's deployment keys:"
    cat /home/apos/.ssh/bitbucket_deploy_key.pub
    read -p "Press Enter to continue after adding the deploy key to Bitbucket..."
fi


########################################
# INSTALL PM2 FOR THE APP USER#
########################################

log_message "Installing PM2 for the app user"
run_command "sudo -H -u \"$APP_USER\" bash -c 'export PATH=/home/apos/.npm-global/bin:\$PATH && npm install -g pm2'"
run_command "sudo -H -u \"$APP_USER\" bash -c 'export PATH=/home/apos/.npm-global/bin:\$PATH && pm2 --version'"


