#!/bin/bash
cd "$(dirname "$0")"
SANDBOX_NAME=$1

if [ -z "$SANDBOX_NAME" ]; then
    echo "Usage: ./start_sandbox.sh <sandbox_name>"
    exit 1
fi

if lxc list | grep -q "$SANDBOX_NAME"; then
    echo "Starting sandbox $SANDBOX_NAME..."
    lxc start $SANDBOX_NAME
    echo "$SANDBOX_NAME started."
else
    echo "Sandbox $SANDBOX_NAME does not exist."
fi