#!/bin/bash
cd "$(dirname "$0")"
HONEYTRAP_NAME="honeytrap"

if lxc list | grep -q "$HONEYTRAP_NAME"; then
    echo "Stopping and deleting Honeytrap..."
    lxc stop $HONEYTRAP_NAME --force
    lxc delete $HONEYTRAP_NAME
    echo "Honeytrap deleted."
else
    echo "Honeytrap does not exist."
fi