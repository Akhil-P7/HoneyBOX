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

# Check if sandbox already exists
if lxc list | grep -q "^| $SANDBOX_NAME "; then
  echo "❌ Error: Sandbox '$SANDBOX_NAME' already exists!"
  exit 1
fi

echo "🔍 Checking for honeytrap..."
# Ensure Honeytrap exists first
if ! lxc list | grep -q "$HONEYTRAP_NAME"; then
  echo "⚠️  Honeytrap not found. Creating honeytrap first..."
  ./create_honeytrap.sh
fi

echo "🚀 Creating sandbox: $SANDBOX_NAME"
echo "⏳ Downloading image and initializing container..."

# Use init + start instead of launch to avoid hanging
# lxc init downloads the image and creates the container
# lxc start starts it without waiting for full initialization

# Run lxc init with output redirected to prevent any blocking
(lxc init ubuntu:20.04 "$SANDBOX_NAME" > /dev/null 2>&1) &
INIT_PID=$!

# Wait maximum 10 seconds for init to complete
for i in {1..10}; do
  if ! ps -p $INIT_PID > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Kill if still running
kill $INIT_PID 2>/dev/null
wait $INIT_PID 2>/dev/null
INIT_EXIT=$?

if [ $INIT_EXIT -eq 0 ]; then
  echo "✅ Container initialized, starting..."
  
  # Start container - use nohup to keep it running after script exits
  nohup lxc start "$SANDBOX_NAME" > /dev/null 2>&1 &
  
  # Give it a moment to begin starting
  sleep 2
  
  # Quick check if container exists (don't query full status which can hang)
  if lxc info "$SANDBOX_NAME" 2>/dev/null | head -1 | grep -q "$SANDBOX_NAME"; then
    echo "✅ Sandbox '$SANDBOX_NAME' created and starting!"
    echo "💡 Container will be fully ready in 30-60 seconds"
    exit 0
  else
    echo "❌ Failed to start sandbox '$SANDBOX_NAME'"
    lxc delete "$SANDBOX_NAME" --force 2>/dev/null
    exit 1
  fi
else
  echo "❌ Failed to initialize sandbox '$SANDBOX_NAME' (exit code: $INIT_EXIT)"
  exit 1
fi
