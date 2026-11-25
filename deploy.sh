#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="promptctrl.json"
DRY_RUN=false

# Colors only on a terminal; NO_COLOR disables, FORCE_COLOR enables (e.g. for tests/pipes).
if [[ -z "${NO_COLOR:-}" && ( -t 1 || -n "${FORCE_COLOR:-}" ) ]]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; DIM=$'\e[2m'; RESET=$'\e[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; DIM=""; RESET=""
fi

for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY_RUN=true ;;
        *) echo "Usage: $0 [-n|--dry-run]"; exit 1 ;;
    esac
done

# Resolve config file path relative to script location
CONFIG_DIR="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"
CONFIG_FILE="$CONFIG_DIR/$(basename "$CONFIG_FILE")"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "${RED}✖ Error: $CONFIG_FILE not found${RESET}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "${RED}✖ Error: jq is not installed${RESET}"
    exit 1
fi

keys=$(jq -r 'keys[]' "$CONFIG_FILE")

for key in $keys; do
    dev_path=$(jq -r --arg k "$key" '.[$k].dev' "$CONFIG_FILE")
    prod_path=$(jq -r --arg k "$key" '.[$k].prod' "$CONFIG_FILE")

    if [[ "$dev_path" == "null" || -z "$dev_path" ]]; then
        echo "${YELLOW}⚠ Warning: Invalid dev path for key $key, skipping${RESET}"
        continue
    fi

    if [[ "$prod_path" == "null" || -z "$prod_path" ]]; then
        echo "${YELLOW}⚠ Warning: Invalid prod path for key $key, skipping${RESET}"
        continue
    fi

    if [[ ! -f "$dev_path" ]]; then
        echo "${YELLOW}⚠ Warning: Dev file $dev_path not found, skipping $key${RESET}"
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ ! -f "$prod_path" ]]; then
            echo "${BLUE}ℹ Dry run: $key would be created at $prod_path${RESET}"
        elif diff -q "$dev_path" "$prod_path" > /dev/null 2>&1; then
            echo "${DIM}○ No changes for $key${RESET}"
        else
            echo "${BLUE}ℹ Dry run: changes for $key (< dev, > prod)${RESET}"
            diff "$dev_path" "$prod_path" || true
        fi
        continue
    fi

    if [[ ! -f "$prod_path" ]]; then
        echo "${BLUE}ℹ Prod file $prod_path does not exist, copying from dev${RESET}"
        cp "$dev_path" "$prod_path"
        echo "${GREEN}✔ Deployed $key${RESET}"
        continue
    fi

    if ! diff -q "$dev_path" "$prod_path" > /dev/null 2>&1; then
        echo "${BLUE}● Changes detected for $key${RESET}"
        # Create backup with timestamp in dev directory
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_filename=$key"_$(basename "$prod_path").backup.${timestamp}"
        backup_path="$(dirname "$CONFIG_FILE")/backup/$backup_filename"
        cp "$prod_path" "$backup_path"
        echo "${DIM}  ↳ Backup created: $backup_path${RESET}"
        # Deploy
        cp "$dev_path" "$prod_path"
        echo "${GREEN}✔ Deployed $key${RESET}"
    else
        echo "${DIM}○ No changes for $key, skipping${RESET}"
    fi
done
