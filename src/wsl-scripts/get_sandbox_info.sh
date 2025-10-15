#!/bin/bash
cd "$(dirname "$0")"
HONEYTRAP_NAME="honeytrap"

echo "Fetching sandbox stats..."

for container in $(lxc list | grep RUNNING | awk '{print $2}'); do
    cpu=$(lxc info $container | grep CPU | awk '{print $2}')
    mem=$(lxc info $container | grep Memory | awk '{print $2, $3}')
    ip=$(lxc list $container -c 4 | grep eth0 | awk '{print $2}')
    
    if [ "$container" == "$HONEYTRAP_NAME" ]; then
        compromised="No"  # Placeholder: later you can detect attacks
        echo "$container (Honeytrap) - CPU: $cpu, MEM: $mem, IP: $ip, Compromised: $compromised"
    else
        echo "$container - CPU: $cpu, MEM: $mem, IP: $ip"
    fi
done