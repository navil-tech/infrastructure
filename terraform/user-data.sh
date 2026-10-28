#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y docker.io docker-compose-v2 nginx certbot python3-certbot-nginx
snap install aws-cli --classic

systemctl enable --now docker
usermod -aG docker ubuntu
