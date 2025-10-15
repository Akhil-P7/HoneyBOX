#!/bin/bash
cd "$(dirname "$0")"
# Input: sandbox name
SANDBOX_NAME=$1
HONEYTRAP_NAME="honeytrap"

if [ -z "$SANDBOX_NAME" ]; then
    echo "Usage: ./create_sandbox.sh <sandbox_name>"
    exit 1
fi

# Ensure Honeytrap exists
if ! lxc list | grep -q "$HONEYTRAP_NAME"; then
    echo "Honeytrap missing! Creating it first..."
    ./create_honeytrap.sh
fi

# Create the sandbox
echo "Creating sandbox $SANDBOX_NAME..."
lxc launch ubuntu:20.04 $SANDBOX_NAME

sleep 3
echo "Sandbox $SANDBOX_NAME created successfully."