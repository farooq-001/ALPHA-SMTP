#!/bin/bash

mkdir -p /opt/docker/system-monitor/

cat <<EOF > /opt/docker/system-monitor/docker-compose.yml
version: '3.8'

services:
  system-monitor:
    build:
      context: .
      dockerfile: Dockerfile
    image: baba001/system-monitor-smtp:v1
    container_name: system-monitor-container
    volumes:
      - ./config.json:/opt/smtp/config.json:ro
    network_mode: host
    restart: unless-stopped
EOF

cat <<EOF > /opt/docker/system-monitor/config.json
{
    "email_sender": "babafarooq001@gmail.com",
    "email_receivers": ["babathaher786@gmail.com", "babafarooq9154@gmail.com"],
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "smtp_username": "babafarooq001@gmail.com",
    "smtp_password": "hulu pver rsvv rmpk",
    "time_zone": "Asia/Kolkata",
    "threshold_disk": 7,
    "threshold_memory": 10,
    "threshold_cpu": 90,
    "check_interval": 60,
    "email_cooldown": 3600
}
EOF

cd /opt/docker/system-monitor/

if docker compose version >/dev/null 2>&1; then
    echo "Using docker compose plugin to start the container..."
    docker compose up -d
elif command -v docker-compose >/dev/null 2>&1; then
    echo "Using docker-compose binary to start the container..."
    docker-compose up -d
else
    echo "Docker Compose is not installed"
    exit 1
fi
