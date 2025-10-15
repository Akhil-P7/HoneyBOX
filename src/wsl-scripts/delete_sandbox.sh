#!/bin/bash
cd "$(dirname "$0")"
SANDBOX_NAME=$1
HONEYTRAP_NAME="honeytrap"

if [ -z "$SANDBOX_NAME" ]; then
    echo "Usage: ./delete_sandbox.sh <sandbox_name>"
    exit 1
fi

# Prevent deletion of Honeytrap
if [ "$SANDBOX_NAME" == "$HONEYTRAP_NAME" ]; then
    echo "Cannot delete Honeytrap manually."
    exit 1
fi

# Delete sandbox
if lxc list | grep -q "$SANDBOX_NAME"; then
    echo "Stopping and deleting sandbox $SANDBOX_NAME..."
    lxc stop $SANDBOX_NAME --force
    lxc delete $SANDBOX_NAME
    echo "Sandbox $SANDBOX_NAME deleted."
else
    echo "Sandbox $SANDBOX_NAME does not exist."
fi

# If no sandboxes remain, delete Honeytrap
SANDBOX_COUNT=$(lxc list | grep -v "$HONEYTRAP_NAME" | grep -c RUNNING)
if [ $SANDBOX_COUNT -eq 0 ]; then
    echo "No sandboxes remaining. Deleting Honeytrap..."
    ./delete_honeytrap.sh
fi