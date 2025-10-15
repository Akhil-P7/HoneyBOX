#!/bin/bash
cd "$(dirname "$0")"
HONEYTRAP_NAME="honeytrap"

echo "Listing all running containers (excluding honeytrap for clarity)..."
lxc list | while read line; do
    container=$(echo $line | awk '{print $2}')
    status=$(echo $line | awk '{print $4}')
    if [[ "$container" != "$HONEYTRAP_NAME" && "$container" != "NAME" ]]; then
        echo "$container - Status: $status"
    fi
done

# Also show honeytrap separately
if lxc list | grep -q "$HONEYTRAP_NAME"; then
    status=$(lxc list | grep "$HONEYTRAP_NAME" | awk '{print $4}')
    echo "$HONEYTRAP_NAME (Honeytrap) - Status: $status"
fi