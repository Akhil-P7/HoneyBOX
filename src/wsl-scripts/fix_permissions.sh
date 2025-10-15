#!/bin/bash
# Fix permissions for all scripts in wsl-scripts directory
cd "$(dirname "$0")"
chmod +x *.sh
echo "All WSL scripts now have execute permissions"