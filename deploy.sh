#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="promptctrl.json"

# Resolve config file path relative to script location
CONFIG_DIR="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"
CONFIG_FILE="$CONFIG_DIR/$(basename "$CONFIG_FILE")"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: $CONFIG_FILE not found"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
    exit 1
fi

keys=$(jq -r 'keys[]' "$CONFIG_FILE")

for key in $keys; do
    dev_path=$(jq -r --arg k "$key" '.[$k].dev' "$CONFIG_FILE")
    prod_path=$(jq -r --arg k "$key" '.[$k].prod' "$CONFIG_FILE")

    if [[ "$dev_path" == "null" || -z "$dev_path" ]]; then
        echo "Warning: Invalid dev path for key $key, skipping"
        continue
    fi

    if [[ "$prod_path" == "null" || -z "$prod_path" ]]; then
        echo "Warning: Invalid prod path for key $key, skipping"
        continue
    fi

    if [[ ! -f "$dev_path" ]]; then
        echo "Warning: Dev file $dev_path not found, skipping $key"
        continue
    fi

    if [[ ! -f "$prod_path" ]]; then
        echo "Prod file $prod_path does not exist, copying from dev"
        cp "$dev_path" "$prod_path"
        echo "Deployed $key"
        continue
    fi

    if ! diff -q "$dev_path" "$prod_path" > /dev/null 2>&1; then
        echo "Changes detected for $key"
        # Create backup with timestamp in dev directory
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_filename="$(basename "$prod_path").backup.${timestamp}"
        backup_path="$(dirname "$dev_path")/$backup_filename"
        cp "$prod_path" "$backup_path"
        echo "Backup created: $backup_path"
        # Deploy
        cp "$dev_path" "$prod_path"
        echo "Deployed $key"
    else
        echo "No changes for $key, skipping"
    fi
done
