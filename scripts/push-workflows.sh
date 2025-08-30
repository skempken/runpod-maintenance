#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/runpod.conf"
LOCAL_WORKFLOWS_DIR="${SCRIPT_DIR}/../workflows"

usage() {
    echo "Usage: $0 [IP_ADDRESS] [SSH_PORT] [OPTIONS]"
    echo "Push ComfyUI workflows to RunPod instance via SSH/rsync"
    echo ""
    echo "Arguments (optional if runpodctl is available):"
    echo "  IP_ADDRESS        IPv4 address of the RunPod instance"
    echo "  SSH_PORT          SSH port exposed by RunPod"
    echo ""
    echo "Options:"
    echo "  -u, --user USER   SSH username (default: root)"
    echo "  -k, --key PATH    SSH private key path (default: ~/.ssh/id_rsa)"
    echo "  -d, --dry-run     Show what would be synced without making changes"
    echo "  -v, --verbose     Enable verbose output"
    echo "  --clean           Delete remote files that don't exist locally"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect running pod"
    echo "  $0 192.168.1.100 22                  # Explicit IP and port"
    echo "  $0 --dry-run --verbose               # Auto-detect with options"
    echo "  $0 192.168.1.100 22 --clean         # Explicit with clean mode"
    echo ""
    echo "Auto-detection requirements:"
    echo "  - runpodctl must be installed and configured"
    echo "  - Exactly one pod must be running"
    echo ""
    echo "Configuration:"
    echo "  Edit config/runpod.conf to set default SSH settings and paths"
    echo ""
    echo "CAUTION:"
    echo "  This script will overwrite files on the RunPod instance!"
    echo "  Use --dry-run first to preview changes."
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file not found: $CONFIG_FILE"
        echo "Run: cp config/runpod.conf.example config/runpod.conf"
        echo "Then edit the configuration file with your RunPod details"
        exit 1
    fi
    
    # Source the config file
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [[ -z "${RUNPOD_WORKFLOWS_PATH:-}" ]]; then
        echo "Error: Missing required configuration in $CONFIG_FILE"
        echo "Required variables: RUNPOD_WORKFLOWS_PATH"
        exit 1
    fi
    
    # Set defaults from config if not overridden
    SSH_USER="${SSH_USER:-${RUNPOD_SSH_USER:-root}}"
    SSH_KEY="${SSH_KEY:-${RUNPOD_SSH_KEY_PATH:-~/.ssh/id_rsa}}"
}

check_dependencies() {
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

detect_pod_details() {
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
        NR > 1 && /RUNNING/ && /->22 \(pub,tcp\)/ {
            # Extract pod ID (first column)
            pod_id = $1
            
            # Find SSH port mapping in PORTS column (last field)
            # Look for pattern like "213.173.105.84:49992->22 (pub,tcp)"
            ports_field = $NF
            
            # Use gsub to extract IP and port from IP:PORT->22 pattern
            if (match(ports_field, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+->22 \(pub,tcp\)/)) {
                # Extract the matching part
                ssh_mapping = substr(ports_field, RSTART, RLENGTH)
                # Split on colon to get IP and port part
                split(ssh_mapping, parts, ":")
                ip = parts[1]
                # Extract port number before ->22
                split(parts[2], port_parts, "->")
                port = port_parts[1]
                print pod_id ":" ip ":" port
            }
        }
    ')
    
    # Count running pods with SSH
    local pod_count
    pod_count=$(echo "$running_pods_info" | grep -c "." 2>/dev/null || echo "0")
    
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
    POD_IP=$(echo "$pod_info" | cut -d: -f2)
    POD_SSH_PORT=$(echo "$pod_info" | cut -d: -f3)
    
    if [[ -z "$POD_IP" || -z "$POD_SSH_PORT" ]]; then
        echo "Error: Could not extract IP address or SSH port from pod details"
        exit 1
    fi
    
    echo "Found running pod: $pod_id"
    echo "Detected pod details: $POD_IP:$POD_SSH_PORT"
}

test_ssh_connection() {
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

ensure_remote_rsync() {
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

check_local_workflows() {
    if [[ ! -d "$LOCAL_WORKFLOWS_DIR" ]]; then
        echo "Error: Local workflows directory not found: $LOCAL_WORKFLOWS_DIR"
        echo "Run pull-workflows.sh first or create the directory manually"
        exit 1
    fi
    
    local workflow_count
    workflow_count=$(find "$LOCAL_WORKFLOWS_DIR" -name "*.json" -type f | wc -l)
    
    if [[ "$workflow_count" -eq 0 ]]; then
        echo "Warning: No workflow files (*.json) found in $LOCAL_WORKFLOWS_DIR"
        echo "Continue anyway? [y/N]"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    else
        echo "Found $workflow_count workflow file(s) to sync"
    fi
}

ensure_remote_directory() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    
    echo "Ensuring remote directory exists: $RUNPOD_WORKFLOWS_PATH"
    
    ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no "$user@$ip" \
        "mkdir -p '$RUNPOD_WORKFLOWS_PATH'" 2>/dev/null || {
        echo "Error: Failed to create remote directory"
        exit 1
    }
}

push_workflows() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local dry_run_flag=""
    local verbose_flag=""
    local delete_flag=""
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        dry_run_flag="--dry-run"
        echo "DRY RUN MODE: No files will be modified"
        echo ""
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        verbose_flag="-v"
    fi
    
    if [[ "${CLEAN:-false}" == "true" ]]; then
        delete_flag="--delete"
        echo "CLEAN MODE: Remote files not in local directory will be deleted"
    fi
    
    echo "Pushing workflows from local directory to RunPod..."
    echo "Local: $LOCAL_WORKFLOWS_DIR"
    echo "Remote: $user@$ip:$port:$RUNPOD_WORKFLOWS_PATH"
    echo ""
    
    # Push workflows via rsync over SSH
    rsync -avz $dry_run_flag $verbose_flag $delete_flag \
        --exclude="*.tmp" \
        --exclude=".DS_Store" \
        --exclude="__pycache__/" \
        -e "ssh -i '$key' -p $port -o StrictHostKeyChecking=no" \
        "$LOCAL_WORKFLOWS_DIR/" \
        "$user@$ip:$RUNPOD_WORKFLOWS_PATH/"
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        echo ""
        echo "Push completed successfully!"
        echo "Remote workflows updated on: $user@$ip:$port:$RUNPOD_WORKFLOWS_PATH"
    fi
}

main() {
    local ip=""
    local port=""
    local dry_run=false
    local verbose=false
    local clean=false
    local auto_detect=false
    
    # Check if first argument looks like an option or if no args provided
    if [[ $# -eq 0 ]] || [[ "${1:-}" =~ ^- ]]; then
        auto_detect=true
    elif [[ $# -eq 1 ]]; then
        echo "Error: If providing IP address, SSH port is also required"
        usage
        exit 1
    else
        # Extract IP and port from first two arguments
        ip="$1"
        port="$2"
        shift 2
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --clean)
                clean=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    export DRY_RUN=$dry_run
    export VERBOSE=$verbose
    export CLEAN=$clean
    
    echo "RunPod ComfyUI Workflow Push"
    echo "============================="
    echo ""
    
    load_config
    check_dependencies
    check_local_workflows
    
    # Auto-detect pod details if needed
    if [[ "$auto_detect" == "true" ]]; then
        detect_pod_details
        ip="$POD_IP"
        port="$POD_SSH_PORT"
    fi
    
    # Expand tilde in SSH key path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    
    # Validate SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Error: SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    test_ssh_connection "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    ensure_remote_rsync "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    ensure_remote_directory "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    push_workflows "$ip" "$port" "$SSH_USER" "$SSH_KEY"
}

main "$@"