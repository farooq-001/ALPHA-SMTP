#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Define the path
TARGET_PATH="/opt/snb-tech"
APP_PATH="$TARGET_PATH/Alpha-Smtp"
VENV_PATH="$APP_PATH/venu"

# Create the target directory if it does not exist
if [ ! -d "$TARGET_PATH" ]; then
    mkdir -p "$TARGET_PATH"
fi

# Unzip the Alpha-Smtp.zip to the target path
unzip Alpha-Smtp.zip -d "$TARGET_PATH"

# Navigate to the application directory
cd "$APP_PATH" || { echo "Application directory not found"; exit 1; }

# Set up Python virtual environment
python3 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

# Install necessary Python packages
pip install flask gunicorn requests psutil

# Copy the service file to the systemd directory
cp -r "$APP_PATH/alpha-smtp.service" /etc/systemd/system/

# Start the service
systemctl daemon-reload
systemctl start alpha-smtp.service

# Optional: enable the service to start on boot
systemctl enable alpha-smtp.service

echo "Setup complete."
