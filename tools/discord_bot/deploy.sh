#!/usr/bin/env bash
# Ship the bot to the live box and restart it. Run from git-bash on Windows or
# any shell with ssh/scp:
#
#   tools/discord_bot/deploy.sh
#
# The token is NOT sent by this script — it is written once, by hand, into
# /etc/astria-discord-bot.env on the server. The counts are not sent either:
# they live in /var/lib/astria-bot and outlive every deploy.
set -euo pipefail

KEY=${ASTRIA_SSH_KEY:-"$HOME/Downloads/LightsailDefaultKey-us-east-2.pem"}
HOST=${ASTRIA_HOST:-ubuntu@3.137.184.94}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# node_modules travels with the bundle: discord.js is pure JavaScript, so the
# tree built on the dev machine runs as-is and the server needs no npm at all.
if [ ! -d "$HERE/node_modules" ]; then
	echo "no node_modules — run 'npm install' in tools/discord_bot first" >&2
	exit 1
fi

echo "[deploy] packing"
BUNDLE=$(mktemp -t astria-bot-XXXXXX.tar.gz)
trap 'rm -f "$BUNDLE"' EXIT
tar -czf "$BUNDLE" -C "$HERE" \
	bot.js package.json package-lock.json src node_modules \
	astria-discord-bot.service README.md

echo "[deploy] sending $(du -h "$BUNDLE" | cut -f1)"
scp -i "$KEY" -o StrictHostKeyChecking=no "$BUNDLE" "$HOST:/tmp/astria-bot.tar.gz"

echo "[deploy] installing"
ssh -i "$KEY" -o StrictHostKeyChecking=no "$HOST" 'bash -s' <<'REMOTE'
set -euo pipefail
sudo install -d -o ubuntu -g ubuntu /opt/astria-bot /var/lib/astria-bot
# Replaced wholesale, so a file deleted upstream does not linger here.
rm -rf /opt/astria-bot/*
tar -xzf /tmp/astria-bot.tar.gz -C /opt/astria-bot
rm -f /tmp/astria-bot.tar.gz

if [ ! -f /etc/astria-discord-bot.env ]; then
	echo "MISSING /etc/astria-discord-bot.env — write DISCORD_BOT_TOKEN=... into it (root:ubuntu 640)" >&2
	exit 1
fi

sudo cp /opt/astria-bot/astria-discord-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now astria-discord-bot.service
sudo systemctl restart astria-discord-bot.service
sleep 3
systemctl --no-pager --lines=15 status astria-discord-bot.service
REMOTE

echo "[deploy] done"
