# Apostrophe CMS Deployment Scripts

This repository contains a set of scripts to deploy, configure, and update an Apostrophe CMS application on an Ubuntu server. The scripts handle the complete deployment process from your local machine to a remote server, supporting zero-downtime deployments via blue/green asset switching, process management via PM2, and integration with Nginx and Varnish.

> **Note:** These scripts assume you'll create a dedicated application user (e.g., `apos`) with passwordless sudo privileges, and that they'll be executed from your local development environment.

---

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Environment File Setup](#environment-file-setup)
- [Deployment Process](#deployment-process)
- [Detailed Scripts Overview](#detailed-scripts-overview)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

These scripts provide an end-to-end deployment solution for Apostrophe CMS applications with the following features:

- **Local to Remote Deployment:** Execute scripts from your local environment to configure and deploy to a remote server
- **PM2-based Process Management:** Zero-downtime deployments with reload/restart functionality
- **Blue/Green Asset Switching:** Deploy front-end assets to standby slots and swap them on successful builds
- **Complete Server Setup:** Automatically install and configure Node.js, Nginx, and Varnish
- **Caching with Varnish:** Custom VCL configuration for proper request forwarding
- **Automated Pre-caching:** Sitemap crawling to prime the cache after deployment

---

## Directory Structure

- **deploy.sh**  
  Main local script that copies all necessary files to the remote server, initiates the deployment, and handles environment file selection.

- **env/**  
  Contains environment files (e.g., `site_1.env`, `site_2.env`) that define variables like `REPO_URL`, `BASE_URL`, `PORT`, etc.

- **lib/** (on remote server after deployment)  
  Contains the scripts that will run on the remote server:
  - **main.sh** - Main driver for Apostrophe CMS setup
  - **config.sh** - Global configuration variables
  - **functions.sh** - Helper functions for logging and command execution
  - **update_install.sh** - System updates and software installation
  - **varnish.sh** - Varnish configuration
  - **nginx.sh** - Nginx configuration
  - **app_user.sh** - Creates application user and directories
  - **apos_user_sudo.sh** - Configures passwordless sudo for the application user
  - **deploy_script.sh** - Creates the deployment script for the app user
  - **post_deploy.sh** - Runs after deployment
  - **cleanup.sh** - Performs cleanup tasks

- **templates/**  
  Contains template files (e.g., `deploy.sh`, `varnish.vcl`) with placeholders that are replaced during deployment.

---

## Prerequisites

Before using these scripts, ensure that:

- **Local Environment:**
  - Bash-compatible shell
  - SSH access to the remote server
  - Appropriate SSH key pair for authentication

- **Remote Server Requirements:**
  - Ubuntu-based server (tested on Ubuntu 20.04 LTS and newer)
  - Ability to run commands with sudo privileges
  - Internet access for downloading packages

- **Bitbucket Access:**
  - The deployment process will generate an SSH key for accessing your Bitbucket repository
  - You'll need to add this key to your Bitbucket repository's deployment keys

---

## Environment File Setup

1. **Create Environment Files:**
   
   Create environment files in the `env/` directory. For example:
   - `env/site_1.env`
   - `env/site_2.env`

   These files should include variables such as:

   ```env
   REPO_URL='git@bitbucket.org:user/site_1.git'
   BASE_URL='https://site_1.co.uk'
   PORT=3000
   PROJECT_SHORTNAME=site_1
   SERVER_IP=your.server.ip.address
   # ...other environment variables as needed
   ```

   **Important:** The `PORT` variable must be set to `3000` for Apostrophe to work properly with the Varnish setup.

2. **Required Environment Variables:**

   - `REPO_URL` - The Git repository URL for your Apostrophe project
   - `BASE_URL` - The base URL where your site will be accessible
   - `PORT` - The port Apostrophe will listen on (should be 3000)
   - `PROJECT_SHORTNAME` - A short name for your project, used in various configurations
   - `SERVER_IP` - Optional, the IP address of your server (if provided, deployment will use this)

---

## Deployment Process

### 1. Make the Script Executable

```bash
chmod +x deploy.sh
```

### 2. Run the Deployment Script

```bash
./deploy.sh
```

### 3. Follow the Prompts

The script will:

1. Prompt for the server username (default: ubuntu)
2. Prompt for PEM file information (default or numbered Lightsail key)
3. Ask you to select an environment file from the `env/` directory
4. Determine the server IP from the environment file or prompt for it
5. Copy all necessary files to the remote server
6. Execute the main setup script on the remote server
7. Generate SSH keys for Bitbucket access (you'll need to add these to your repository)
8. Install and configure all required software
9. Deploy your Apostrophe application

### 4. Add the Deploy Key to Bitbucket

During the deployment process, you'll be prompted to add an SSH deploy key to your Bitbucket repository. The key will be displayed in the terminal. You need to add this key to your repository's deployment keys in Bitbucket before continuing.

---

## Detailed Scripts Overview

### deploy.sh

- **Purpose:** Main entry point executed locally
- **Functionality:**
  - Selects environment file
  - Copies all scripts to the remote server
  - Executes the setup process remotely

### main.sh

- **Purpose:** Main driver for remote setup
- **Functionality:**
  - Orchestrates the execution of all other scripts
  - Handles user creation, system updates, and service configuration

### update_install.sh

- **Purpose:** Updates the system and installs required software
- **Functionality:**
  - Updates system packages
  - Installs Node.js 22.x
  - Installs Nginx and Varnish

### nginx.sh & varnish.sh

- **Purpose:** Configures the web server and caching proxy
- **Functionality:**
  - Sets up Nginx to forward traffic to Varnish (port 81)
  - Configures Varnish to forward requests to Apostrophe (port 3000)

### app_user.sh & apos_user_sudo.sh

- **Purpose:** Sets up the application user
- **Functionality:**
  - Creates the `apos` user
  - Configures passwordless sudo
  - Sets up SSH keys for Git access
  - Installs PM2 for the application user

### deploy_script.sh

- **Purpose:** Creates the deployment script for the application user
- **Functionality:**
  - Customizes the deploy script with repository URL
  - Places it in the appropriate directory

### sitemap-crawler.js

- **Purpose:** Pre-caches the site after deployment
- **Functionality:**
  - Crawls the sitemap.xml
  - Visits all URLs to prime the cache

---

## Troubleshooting

### Port Configuration Issues
- **Important:** Ensure your Apostrophe application is configured to listen on port 3000
  - Check your `.env` file to confirm that `PORT=3000` is set
  - The Varnish configuration expects Apostrophe to be running on port 3000
  - If you need to use a different port, you must update the Varnish VCL file accordingly

### Varnish Connection Issues
- If Varnish cannot connect to the backend:
  - Check that Apostrophe is running: `pm2 list`
  - Verify Varnish configuration: `sudo varnishd -C -f /etc/varnish/default.vcl`
  - Test direct connection to Apostrophe: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000`
  - Test connection to Varnish: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:81`

### PM2 Process Issues
- If Apostrophe fails to start or restart:
  - Check PM2 logs: `pm2 logs apostrophe`
  - Verify `NODE_ENV` is properly set in your environment file
  - Try manually starting the application: `cd /var/www/apostrophe && pm2 start app.js --name apostrophe`

### Deployment Key Issues
- If you encounter authentication failures with Bitbucket:
  - Verify the deploy key was added to your Bitbucket repository
  - Check SSH configuration: `sudo -u apos ssh -T git@bitbucket.org`
  - Ensure proper permissions: `ls -la /home/apos/.ssh/`

### File Permission Issues
- If you encounter permission errors:
  - Check ownership of application directory: `ls -la /var/www/apostrophe`
  - Ensure the apos user has proper permissions: `sudo chown -R apos:apos /var/www/apostrophe`
  - Verify sudo privileges: `sudo -u apos sudo -n true`

### Unreplaced Placeholders
- If you see unreplaced placeholders like `$REPO_URL$` in scripts:
  - Check that your environment file is properly formatted
  - Verify the substitution process in `deploy_script.sh`

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