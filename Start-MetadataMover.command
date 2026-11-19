#!/bin/bash
# HQR Metadata Mover launcher for macOS. Double-click this file (first time: right-click > Open).
cd "$(dirname "$0")" || exit 1

NODE="$(command -v node)"
if [ -z "$NODE" ]; then
  for c in /opt/homebrew/bin/node /usr/local/bin/node "$HOME/.nvm/versions/node"/*/bin/node; do
    [ -x "$c" ] && NODE="$c" && break
  done
fi
if [ -z "$NODE" ]; then
  echo
  echo "HQR Metadata Mover needs Node.js (version 18 or newer), which is free."
  echo "Install the LTS version from https://nodejs.org, then double-click this file again."
  open "https://nodejs.org" 2>/dev/null
  echo; read -n 1 -s -r -p "Press any key to close."; exit 1
fi

if ! command -v sf >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/sf ] && [ ! -x /usr/local/bin/sf ]; then
  echo "Note: the Salesforce CLI (sf) was not found. Install it from https://developer.salesforce.com/tools/salesforcecli"
fi

echo "Starting HQR Metadata Mover. Leave this window open while you use it; close it to stop."
exec "$NODE" server.mjs
