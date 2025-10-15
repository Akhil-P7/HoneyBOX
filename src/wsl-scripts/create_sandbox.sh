#!/bin/bash
cd "$(dirname "$0")"
# Usage: ./create_sandbox.sh <sandbox_name>
# Creates a normal sandbox. Honeytrap is created automatically if not existing

SANDBOX_NAME=$1
HONEYTRAP_NAME="honeytrap"

if [ -z "$SANDBOX_NAME" ]; then
  echo "Error: Provide a sandbox name"
  exit 1
fi

# Ensure Honeytrap exists first
if ! lxc list | grep -q "$HONEYTRAP_NAME"; then
  ./create_honeytrap.sh
fi

# Launch normal sandbox
lxc launch ubuntu:20.04 "$SANDBOX_NAME"
