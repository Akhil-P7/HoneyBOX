# HoneyBOX Honeytrap Template Builder

## What This Script Does

`build_honeytrap_template.sh` creates a pre-configured LXD container image (template) with:
- **DVWA** (Damn Vulnerable Web Application) - Intentionally vulnerable web app
- **Cowrie** - SSH honeypot to log attacker interactions
- **Apache + MariaDB** - Web server and database
- **PCAP Rotator** - Captures network traffic for analysis

This template can then be used to quickly spin up honeytrap containers.

---

## Prerequisites

1. **WSL2 installed** with Ubuntu
2. **LXD installed and initialized** in WSL
3. **Sufficient permissions** to run LXD commands

---

## How to Run in WSL

### Method 1: Direct Execution (Recommended)

```bash
# From PowerShell, navigate to the script directory
cd C:\Users\harsh\Desktop\HoneyBOX\honeybox-setup

# Run the script in WSL
wsl bash ./build_honeytrap_template.sh
```

### Method 2: From Inside WSL

```bash
# Open WSL
wsl

# Navigate to the script directory (use /mnt/c for Windows paths)
cd /mnt/c/Users/harsh/Desktop/HoneyBOX/honeybox-setup

# Make the script executable (if not already)
chmod +x build_honeytrap_template.sh

# Run the script
./build_honeytrap_template.sh
```

---

## Expected Output

The script will:
1. ✅ Clean up any existing builder containers
2. ✅ Launch a new Ubuntu 20.04 container
3. ✅ **Check DNS and apply fallback if needed** (NEW!)
4. ✅ Update and upgrade packages with retry logic
5. ✅ Install Apache, PHP, MariaDB, Python, tcpdump
6. ✅ Configure MariaDB for DVWA
7. ✅ Clone and setup DVWA
8. ✅ Install and configure Cowrie SSH honeypot
9. ✅ Create PCAP rotation service
10. ✅ Publish as LXD image alias `honeytrap-template`
11. ✅ Clean up builder container

**Estimated time:** 5-10 minutes depending on your internet speed.

---

## What Changed (DNS Fix)

### Problem
In WSL/LXD environments, containers sometimes fail to resolve DNS names (like `archive.ubuntu.com`), causing `apt-get update` to fail.

### Solution Added
Before running `apt-get update`, the script now:

1. **Tests DNS connectivity:**
   ```bash
   timeout 5 bash -c "getent hosts archive.ubuntu.com >/dev/null 2>&1"
   ```
   - Tries to resolve `archive.ubuntu.com`
   - Times out after 5 seconds if it hangs

2. **Applies DNS fallback if test fails:**
   ```bash
   echo "nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null
   ```
   - Temporarily sets Google's public DNS (8.8.8.8)
   - Ensures the container can resolve package repositories

3. **Retries apt-get update up to 4 times:**
   ```bash
   until apt-get update || [ $retries -ge 4 ]; do
     sleep 5
     retries=$((retries+1))
   done
   ```
   - If `apt-get update` fails, waits 5 seconds and retries
   - Aborts after 4 failed attempts with clear error message

### Benefits
- ✅ **Automatic recovery** from DNS issues
- ✅ **Retry logic** handles temporary network glitches
- ✅ **Clear error messages** if build truly fails
- ✅ **No manual intervention** needed

---

## Verify the Template Was Created

After the script completes successfully:

```bash
# List LXD images
wsl lxc image list

# You should see:
# +-------------------+--------+--------+-------------+
# |       ALIAS       | PUBLIC | TYPE   | DESCRIPTION |
# +-------------------+--------+--------+-------------+
# | honeytrap-template| no     | CONTAINER | ...      |
# +-------------------+--------+--------+-------------+
```

---

## Using the Template

Once the template is built, you can create honeytrap containers instantly:

```bash
# Create a honeytrap from the template
wsl lxc init honeytrap-template my-honeytrap-01

# Start it
wsl lxc start my-honeytrap-01

# Check status
wsl lxc list
```

---

## Troubleshooting

### Script fails with "DNS lookup failed"
- **Cause:** WSL networking issue or no internet connection
- **Fix:** Check internet connection, restart WSL: `wsl --shutdown` then reopen

### "lxc command not found"
- **Cause:** LXD not installed in WSL
- **Fix:** Install LXD: `sudo snap install lxd` then initialize: `sudo lxd init`

### "Permission denied" errors
- **Cause:** User not in lxd group
- **Fix:** Add user to group: `sudo usermod -a -G lxd $USER` then logout/login

### Build takes too long / hangs
- **Cause:** Slow internet or container initialization delay
- **Solution:** Wait patiently, first build downloads ~500MB of packages

---

## Script Location
`C:\Users\harsh\Desktop\HoneyBOX\honeybox-setup\build_honeytrap_template.sh`

## Quick Start Command
```powershell
cd C:\Users\harsh\Desktop\HoneyBOX\honeybox-setup
wsl bash ./build_honeytrap_template.sh
```
