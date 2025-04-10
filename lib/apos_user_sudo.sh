#!/bin/bash
# Simple script to fix passwordless sudo for apos user
# Run this script as root or with sudo

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo"
  exit 1
fi

echo "Setting up simpler passwordless sudo for apos user..."

# Create a temporary file
TEMP_SUDOERS=$(mktemp)
cat > "$TEMP_SUDOERS" << 'EOF'
# Allow apos user to run ALL commands without password
# NOTE: This is less secure than using specific commands,
# but is the simplest solution for deployment scripts
apos ALL=(ALL) NOPASSWD: ALL
EOF

# Validate the sudoers file
visudo -cf "$TEMP_SUDOERS"
if [ $? -ne 0 ]; then
  echo "Invalid sudoers file. Please check the syntax."
  rm "$TEMP_SUDOERS"
  exit 1
fi

# Move the file to the proper location
mv "$TEMP_SUDOERS" /etc/sudoers.d/apos
chmod 440 /etc/sudoers.d/apos

echo "Sudoers file created and permissions set"

# Verify the configuration
echo "Verifying sudoers configuration..."
visudo -c
if [ $? -eq 0 ]; then
  echo "Sudoers configuration is valid"
else
  echo "Sudoers configuration is invalid. Please check the file manually."
  exit 1
fi

# Test the configuration
echo "Testing the configuration..."
if sudo -u apos sudo -n true 2>/dev/null; then
  echo "Test successful. The apos user now has passwordless sudo privileges."
else
  echo "Test failed. Please check the configuration manually."
fi

echo "Setup complete."