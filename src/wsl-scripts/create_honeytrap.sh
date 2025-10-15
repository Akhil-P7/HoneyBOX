#!/bin/bash
cd "$(dirname "$0")"
# Creates the honeytrap container for security monitoring

HONEYTRAP_NAME="honeytrap"

echo "🍯 Creating honeytrap container..."

# Check if honeytrap already exists
if lxc list | grep -q "^| $HONEYTRAP_NAME "; then
  echo "✅ Honeytrap already exists!"
  lxc list "^$HONEYTRAP_NAME$"
  exit 0
fi

echo "⏳ Initializing honeytrap container..."

# Use init + start instead of launch to avoid hanging
# Run in background with timeout
(lxc init ubuntu:20.04 "$HONEYTRAP_NAME" > /dev/null 2>&1) &
INIT_PID=$!

# Wait maximum 10 seconds
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
  echo "✅ Honeytrap initialized, starting..."
  
  # Start container - use nohup to keep it running after script exits
  nohup lxc start "$HONEYTRAP_NAME" > /dev/null 2>&1 &
  
  # Give it a moment
  sleep 2
  
  # Quick check if container exists
  if lxc info "$HONEYTRAP_NAME" 2>/dev/null | head -1 | grep -q "$HONEYTRAP_NAME"; then
    echo "✅ Honeytrap created and starting!"
    exit 0
  else
    echo "❌ Failed to start honeytrap"
    lxc delete "$HONEYTRAP_NAME" --force 2>/dev/null
    exit 1
  fi
else
  echo "❌ Failed to initialize honeytrap (exit code: $INIT_EXIT)"
  exit 1
fi