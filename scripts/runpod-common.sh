#!/bin/bash

# RunPod Common Library
# Shared functions for RunPod automation scripts
#
# Copyright (c) 2025 Sebastian Kempken
# Licensed under the MIT License - see LICENSE file for details

# Get the directory where this library is located
RUNPOD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNPOD_CONFIG_FILE="${RUNPOD_LIB_DIR}/../config/runpod.conf"

load_runpod_config() {
    if [[ ! -f "$RUNPOD_CONFIG_FILE" ]]; then
        echo "Error: Configuration file not found: $RUNPOD_CONFIG_FILE"
        echo "Run: cp config/runpod.conf.example config/runpod.conf"
        echo "Then edit the configuration file with your RunPod details"
        exit 1
    fi
    
    # Source the config file
    # shellcheck source=/dev/null
    source "$RUNPOD_CONFIG_FILE"
    
    # Validate required variables
    if [[ -z "${RUNPOD_WORKFLOWS_PATH:-}" ]]; then
        echo "Error: Missing required configuration in $RUNPOD_CONFIG_FILE"
        echo "Required variables: RUNPOD_WORKFLOWS_PATH"
        exit 1
    fi
    
    # Set defaults from config if not overridden
    SSH_USER="${SSH_USER:-${RUNPOD_SSH_USER:-root}}"
    SSH_KEY="${SSH_KEY:-${RUNPOD_SSH_KEY_PATH:-~/.ssh/id_rsa}}"
}

check_runpod_dependencies() {
    if ! command -v rsync >/dev/null 2>&1; then
        echo "Error: rsync not found. Please install it:"
        echo "  macOS: brew install rsync"
        echo "  Linux: apt-get install rsync or yum install rsync"
        exit 1
    fi
    
    if ! command -v ssh >/dev/null 2>&1; then
        echo "Error: ssh not found. Please install openssh-client"
        exit 1
    fi
}

detect_runpod_details() {
    if ! command -v runpodctl >/dev/null 2>&1; then
        echo "Error: runpodctl not found. Please install it or provide IP and port manually."
        echo "  Install: https://github.com/runpod/runpodctl"
        exit 1
    fi
    
    echo "Auto-detecting running RunPod instance..."
    
    # Get list of all pods
    local pod_output
    pod_output=$(runpodctl get pod -a 2>/dev/null) || {
        echo "Error: Failed to get pod list from runpodctl"
        echo "Please ensure runpodctl is configured with valid API key"
        exit 1
    }
    
    # Parse output to get running pods with SSH ports
    # Skip header line and filter for RUNNING status with SSH port (->22)
    local running_pods_info
    running_pods_info=$(echo "$pod_output" | awk '
        NR > 1 && /RUNNING/ && /->22/ {
            pod_id = $1
            # Look for IP:PORT->22 pattern in the whole line
            if (match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+->22/)) {
                # Extract the matched substring
                ssh_part = substr($0, RSTART, RLENGTH)
                # Remove the ->22 part
                gsub(/->22.*/, "", ssh_part)
                # Split IP:PORT
                split(ssh_part, addr_parts, ":")
                if (length(addr_parts) == 2) {
                    ip = addr_parts[1]
                    port = addr_parts[2]
                    print pod_id ":" ip ":" port
                }
            }
        }
    ')
    
    # Count running pods with SSH
    local pod_count
    if [[ -z "$running_pods_info" ]]; then
        pod_count=0
    else
        pod_count=$(echo "$running_pods_info" | grep -c ":" 2>/dev/null || echo "0")
    fi
    
    if [[ "$pod_count" -eq 0 ]]; then
        echo "Error: No running pods with SSH port found"
        echo "Please ensure a pod is running with SSH port exposed or provide IP and port manually"
        exit 1
    fi
    
    if [[ "$pod_count" -gt 1 ]]; then
        echo "Error: Multiple running pods with SSH found ($pod_count)"
        echo "Please specify IP and port manually or ensure only one pod is running"
        echo "Running pods:"
        echo "$running_pods_info" | cut -d: -f1
        exit 1
    fi
    
    # Parse the single running pod info
    local pod_info
    pod_info=$(echo "$running_pods_info" | head -1)
    local pod_id
    pod_id=$(echo "$pod_info" | cut -d: -f1)
    DETECTED_POD_IP=$(echo "$pod_info" | cut -d: -f2)
    DETECTED_POD_SSH_PORT=$(echo "$pod_info" | cut -d: -f3)
    
    if [[ -z "$DETECTED_POD_IP" || -z "$DETECTED_POD_SSH_PORT" ]]; then
        echo "Error: Could not extract IP address or SSH port from pod details"
        exit 1
    fi
    
    echo "Found running pod: $pod_id"
    echo "Detected pod details: $DETECTED_POD_IP:$DETECTED_POD_SSH_PORT"
}

test_runpod_ssh_connection() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    
    echo "Testing SSH connection to $user@$ip:$port..."
    
    if ! ssh -i "$key" -p "$port" -o ConnectTimeout=10 -o BatchMode=yes \
         -o StrictHostKeyChecking=no "$user@$ip" "echo 'SSH connection successful'" 2>/dev/null; then
        echo "Error: Cannot establish SSH connection to $user@$ip:$port"
        echo "Please check:"
        echo "  - IP address and port are correct"
        echo "  - SSH key path: $key"
        echo "  - RunPod instance is running and SSH is enabled"
        echo "  - Network connectivity"
        exit 1
    fi
    
    echo "SSH connection test successful!"
}

ensure_runpod_remote_rsync() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    
    echo "Checking rsync availability on remote system..."
    
    if ! ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no "$user@$ip" \
         "command -v rsync >/dev/null 2>&1" 2>/dev/null; then
        echo "rsync not found on remote system. Installing..."
        
        ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no "$user@$ip" \
            "apt update >/dev/null 2>&1 && apt install -y rsync >/dev/null 2>&1" || {
            echo "Error: Failed to install rsync on remote system"
            echo "Please install rsync manually on the RunPod instance:"
            echo "  apt update && apt install -y rsync"
            exit 1
        }
        
        echo "rsync installed successfully on remote system"
    else
        echo "rsync is available on remote system"
    fi
}

setup_runpod_ssh_key() {
    # Expand tilde in SSH key path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    
    # Validate SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Error: SSH key not found: $SSH_KEY"
        exit 1
    fi
}

prepare_runpod_connection() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    
    test_runpod_ssh_connection "$ip" "$port" "$user" "$key"
    ensure_runpod_remote_rsync "$ip" "$port" "$user" "$key"
}