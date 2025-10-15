#!/bin/bash
cd "$(dirname "$0")"
SANDBOX_NAME=$1
HONEYTRAP_NAME="honeytrap"

if [ -z "$SANDBOX_NAME" ]; then
    echo "Usage: ./stop_sandbox.sh <sandbox_name>"
    exit 1
fi

# Prevent manual stop of Honeytrap
if [ "$SANDBOX_NAME" == "$HONEYTRAP_NAME" ]; then
    echo "Cannot manually stop Honeytrap."
    exit 1
fi

if lxc list | grep -q "$SANDBOX_NAME"; then
    echo "Stopping sandbox $SANDBOX_NAME..."
    lxc stop $SANDBOX_NAME --force
    echo "$SANDBOX_NAME stopped."
else
    echo "Sandbox $SANDBOX_NAME does not exist."
fi