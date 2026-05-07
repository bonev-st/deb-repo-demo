#!/usr/bin/env bash
# lib.sh — shared helpers; sourced by all publish scripts after config.sh

# require_config VAR … — exit 1 if any variable is empty or unset
require_config() {
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            echo "ERROR: $var must be set in config.sh" >&2
            exit 1
        fi
    done
}

# require_cmds CMD … — exit 1 if any command is not on PATH
require_cmds() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ERROR: required command '$cmd' not found. Install it first." >&2
            exit 1
        fi
    done
}

# safe_component NAME VALUE — exit 1 if VALUE contains chars outside [A-Za-z0-9._-]
safe_component() {
    local name="$1" val="$2"
    if [[ ! "$val" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "ERROR: $name must match [A-Za-z0-9._-], got: '$val'" >&2
        exit 1
    fi
}
