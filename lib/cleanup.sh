#!/bin/bash
# cleanup.sh - Clean up after installation

log_message "Performing cleanup tasks"
run_command "apt autoremove -y"