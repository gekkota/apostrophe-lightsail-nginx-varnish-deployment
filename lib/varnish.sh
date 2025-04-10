#!/bin/bash
# varnish.sh - Configure Varnish and override systemd settings using our custom VCL template
#
# Assumes the existence of helper functions: log_message, run_command

# --- Step 1: Configure /etc/default/varnish ---

DESIRED_DEFAULT_VARNISH=$(cat <<'EOF'
# Default settings for varnish
START=yes
NFILES=131072
MEMLOCK=82000
DAEMON_OPTS="-a :81 \
-T localhost:6082 \
-f /etc/varnish/default.vcl \
-S /etc/varnish/secret \
-s malloc,256m"
EOF
)

if [ ! -f /etc/default/varnish ] || ! diff -q /etc/default/varnish <(echo "$DESIRED_DEFAULT_VARNISH") >/dev/null 2>&1; then
    log_message "Writing default Varnish settings to /etc/default/varnish"
    echo "$DESIRED_DEFAULT_VARNISH" > /etc/default/varnish
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to write /etc/default/varnish"
        exit 1
    fi
else
    log_message "/etc/default/varnish is already configured."
fi

# --- Step 2: Copy Custom VCL Template to /etc/varnish/default.vcl ---

CUSTOM_VCL_TEMPLATE="$(dirname "$0")/templates/varnish.vcl"
if [ ! -f "$CUSTOM_VCL_TEMPLATE" ]; then
    log_message "Error: Custom VCL template not found at $CUSTOM_VCL_TEMPLATE"
    exit 1
fi

if [ ! -f /etc/varnish/default.vcl ] || ! diff -q "$CUSTOM_VCL_TEMPLATE" /etc/varnish/default.vcl >/dev/null 2>&1; then
    log_message "Copying custom VCL template from $CUSTOM_VCL_TEMPLATE to /etc/varnish/default.vcl"
    cp "$CUSTOM_VCL_TEMPLATE" /etc/varnish/default.vcl
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to copy custom VCL template"
        exit 1
    fi
else
    log_message "/etc/varnish/default.vcl already matches the custom template."
fi

# --- Step 3: Create Varnish Secret File if Needed ---

if [ ! -f /etc/varnish/secret ]; then
    log_message "Creating Varnish secret file"
    run_command "echo \"randomsecret\" > /etc/varnish/secret"
    run_command "chmod 600 /etc/varnish/secret"
else
    log_message "/etc/varnish/secret already exists."
fi

# --- Step 4: Enable Varnish Service ---

log_message "Enabling Varnish service"
run_command "systemctl enable varnish"

# --- Step 5: Override systemd Service for Varnish ---

OVERRIDE_CONTENT=$(cat <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/varnishd -j unix,user=varnish -F -a :81 -T localhost:6082 -f /etc/varnish/default.vcl -S /etc/varnish/secret -s malloc,256m
EOF
)

OVERRIDE_DIR="/etc/systemd/system/varnish.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"

if [ ! -d "$OVERRIDE_DIR" ]; then
    run_command "mkdir -p $OVERRIDE_DIR"
fi

if [ ! -f "$OVERRIDE_FILE" ] || ! diff -q "$OVERRIDE_FILE" <(echo "$OVERRIDE_CONTENT") >/dev/null 2>&1; then
    log_message "Overriding Varnish systemd service to listen on port 81"
    echo "$OVERRIDE_CONTENT" > "$OVERRIDE_FILE"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to write systemd override file"
        exit 1
    fi
else
    log_message "Systemd override for Varnish is already in place."
fi

# --- Step 6: Reload Systemd and Restart Varnish ---

log_message "Reloading systemd daemon..."
run_command "systemctl daemon-reload"
log_message "Restarting Varnish to apply changes..."
run_command "systemctl restart varnish"