# Apostrophe CMS Deployment Scripts

This repository contains a set of scripts to deploy, configure, and update an Apostrophe CMS application on an Ubuntu server. The scripts support zero-downtime deployments via blue/green asset switching, process management via PM2, and integration with Nginx and Varnish.

> **Note:** These scripts assume that you have a dedicated application user (e.g., `apos`) with passwordless sudo privileges (configured via `apos_user_sudo.sh`), and that necessary environment files and template files are in place.

---

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Environment File Setup](#environment-file-setup)
- [Scripts Overview](#scripts-overview)
- [Usage Instructions](#usage-instructions)
  - [1. System Update & Software Installation](#1-system-update--software-installation)
  - [2. Configuring Nginx](#2-configuring-nginx)
  - [3. Configuring Varnish](#3-configuring-varnish)
  - [4. Application Deployment Process](#4-application-deployment-process)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

These scripts deploy an Apostrophe CMS application with the following features:

- **PM2-based Process Management:** Zero-downtime deployments with reload/restart functionality.
- **Blue/Green Asset Switching:** Deploy front-end assets to standby slots and swap them on successful builds.
- **Reverse Proxy Setup:** Nginx is configured to forward traffic to Varnish.
- **Caching with Varnish:** Custom VCL configuration is applied to Varnish so that it forwards requests to the correct backend port.

---

## Directory Structure

- **deploy_script.sh**  
  Main deployment script that prepares the environment, updates the repository, builds assets, and reloads the application via PM2.

- **config.sh**  
  Contains shared configuration variables and settings.

- **nginx.sh**  
  Configures Nginx to proxy requests to Varnish by creating the proper site configuration, symlinks, and reloading Nginx.

- **varnish.sh**  
  Configures Varnish by writing default settings, copying custom VCL templates, creating a secret file, and setting up a systemd override.

- **update_install.sh**  
  Updates the system and installs required packages (Node.js 22.x, Nginx, Varnish) with checks to avoid unnecessary reinstallation.

- **functions.sh**  
  Contains helper functions (e.g., `log_message`, `run_command`) used by other scripts.

- **app_user.sh & apos_user_sudo.sh**  
  Scripts to set up the application user and configure passwordless sudo privileges.

- **deploy.sh**  
  Deployment template that is copied (with variable substitution) to the deployment directory. It handles pulling the latest code from the repository, installing dependencies, building assets, and managing PM2.

- **main.sh**  
  The main entry point for starting the Apostrophe CMS application using PM2.

- **env/**  
  Contains environment files (e.g., `entertainers.env`, `threekey.env`). These files define variables like `REPO_URL`, `BASE_URL`, `PORT`, `PROJECT_SHORTNAME`, etc.

- **templates/**  
  Contains template files (e.g., `deploy.sh`, `varnish.vcl`) with placeholders (e.g., `$REPO_URL$`, `$APP_NAME$`) that are replaced during deployment.

---

## Prerequisites

Before using these scripts, ensure that:

- **Operating System:** You are running an Ubuntu-based server.
- **User Setup:** A dedicated application user (e.g., `apos`) is set up with passwordless sudo privileges.
- **Software Requirements:**  
  - Git, Node.js, and PM2 are installed.
  - Nginx and Varnish are installed or will be installed by `update_install.sh`.
- **Environment Files:** Prepared in the local `env/` directory.
- **Template Files:** Custom template files are available in the `templates/` directory.
- **Remote Environment:** The selected environment file will be deployed to `/opt/env/apostrophe.env` and linked as `.env` in the application directory.

---

## Environment File Setup

1. **Local Environment Files:**  
   Place your environment files inside the `env/` directory. For example:
   - `env/entertainers.env`
   - `env/threekey.env`

   These files should include variables such as:

   ```env
   REPO_URL='git@bitbucket.org:lev_lev/threekey-a3.git'
   BASE_URL='https://entertainers.co.uk'
   PORT=3000
   PROJECT_SHORTNAME=entertainers
   SERVER_IP=your.server.ip.address
   # ...other environment variables as needed
   ```

2. **Remote Deployment:**  
   During the deployment process, you select one of these environment files. The chosen file is copied to the remote server as `/opt/env/apostrophe.env` and is linked in the application directory as `.env` for use by the application.

---

## Scripts Overview

### update_install.sh

- **Purpose:**  
  Updates the system, installs Node.js (22.x), Nginx, and Varnish.
- **Functionality:**  
  - Runs `apt update` and `apt upgrade`.
  - Checks if Node.js 22.x is installed; if not, installs the correct version.
  - Installs Nginx and Varnish if they are not already installed.

### nginx.sh

- **Purpose:**  
  Configures Nginx to proxy requests to Varnish.
- **Functionality:**  
  - Writes the desired Nginx configuration to `/etc/nginx/sites-available/varnish_proxy`.
  - Creates (or updates) the symbolic link in `/etc/nginx/sites-enabled/`.
  - Removes the default site configuration.
  - Tests and reloads Nginx.
- **Checks:**  
  Compares current configuration with the desired configuration to avoid unnecessary overwrites.

### varnish.sh

- **Purpose:**  
  Configures Varnish.
- **Functionality:**  
  - Writes default settings to `/etc/default/varnish`.
  - Copies your custom VCL template to `/etc/varnish/default.vcl`.
  - Creates a Varnish secret file if it does not exist.
  - Sets up a systemd service override for Varnish and restarts the service.
- **Checks:**  
  Validates file existence and content before making changes.

### deploy_script.sh & deploy.sh

- **Purpose:**  
  Deploys the application.
- **Functionality:**  
  - Prompts you to select an environment file from the `env/` directory.
  - Copies necessary files to the remote server.
  - Replaces placeholders (e.g., `$REPO_URL$`, `$APP_NAME$`) in the templates.
  - Updates the repository, installs dependencies, builds assets, and manages PM2 to reload or restart the application.
  - Implements blue/green asset switching.
  
### functions.sh

- **Purpose:**  
  Provides shared helper functions (e.g., `log_message`, `run_command`) for logging and command execution.

### app_user.sh & apos_user_sudo.sh

- **Purpose:**  
  Set up the application user and configure passwordless sudo privileges.

### main.sh

- **Purpose:**  
  The entry point for starting the Apostrophe CMS application via PM2.

---

## Usage Instructions

### 1. System Update & Software Installation

Run the **update_install.sh** script (as root or with sudo):

```bash
sudo bash update_install.sh
```

This script:
- Updates the system.
- Installs or upgrades Node.js (22.x), Nginx, and Varnish as required.

### 2. Configuring Nginx

Run the nginx.sh script:

```bash
sudo bash nginx.sh
```

This script:
- Writes the desired configuration to `/etc/nginx/sites-available/varnish_proxy`.
- Creates the necessary symbolic link in `/etc/nginx/sites-enabled/`.
- Removes the default configuration.
- Tests and reloads Nginx.

### 3. Configuring Varnish

Run the varnish.sh script:

```bash
sudo bash varnish.sh
```

This script:
- Writes default settings to `/etc/default/varnish`.
- Copies your custom VCL template to `/etc/varnish/default.vcl`.
- Creates a secret file for Varnish if needed.
- Sets up a systemd override for Varnish and restarts the service.

### 4. Application Deployment Process

1. **Environment File Selection:**
   Run the deploy_script.sh locally. When prompted, select an environment file from the `env/` directory. The selected file will be copied to `.env` and later deployed to `/opt/env/apostrophe.env` on the remote server.

2. **Deploy the Application:**
   Execute the deployment script:

   ```bash
   ./deploy_script.sh
   ```

   This script will:
   - Copy necessary files to the remote server.
   - Replace placeholders (e.g., `$REPO_URL$`, `$APP_NAME$`) in template files.
   - Update the repository, install dependencies, build assets, and manage the application with PM2.
   - Switch asset slots using a blue/green deployment strategy.
   - Verify service connectivity for Varnish (or Nginx) and optionally trigger pre-caching with a sitemap crawler.

---

## Troubleshooting

- **Port Mismatch:**
  If Varnish forwards to an unexpected port (e.g., 3001 instead of 3000), verify that your application is configured to listen on the correct port (usually defined in your `.env` file as `PORT=3000`) and check your PM2 logs.

- **Unreplaced Placeholders:**
  If placeholders such as `$REPO_URL$` or `$APP_NAME$` remain in deployed scripts:
  - Ensure that the correct environment file is sourced (check `/opt/env/apostrophe.env` on the server).
  - Confirm that the template files in `templates/` contain the exact placeholder strings.
  - Verify that the variable substitution (using `sed` in `deploy_script.sh`) is functioning properly.

- **PM2 and Process Issues:**
  - Use `pm2 logs <app_name>` to review logs.
  - Use `pm2 list` to verify running processes.

- **Nginx & Varnish Connectivity:**
  - Test Nginx with:
    ```bash
    curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1
    ```
  - Test Varnish with:
    ```bash
    curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:81
    ```
  - Check service statuses with:
    ```bash
    systemctl status nginx
    systemctl status varnish
    ```

- **File Permissions & Ownership:**
  Verify that files are owned by the appropriate user (typically `apos`) and have proper permissions using `chown` and `chmod` as shown in the scripts.

- **Sudo Privileges:**
  If permission errors occur, ensure that the `apos` user has passwordless sudo privileges for the required commands (check via `visudo -c`).

---

## License


MIT License

Copyright (c) 2025 Gekkota

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---
