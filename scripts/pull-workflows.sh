#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/runpod.conf"
LOCAL_WORKFLOWS_DIR="${SCRIPT_DIR}/../workflows"

usage() {
    echo "Usage: $0 <IP_ADDRESS> <SSH_PORT> [OPTIONS]"
    echo "Pull ComfyUI workflows from RunPod instance via SSH/rsync"
    echo ""
    echo "Arguments:"
    echo "  IP_ADDRESS        IPv4 address of the RunPod instance"
    echo "  SSH_PORT          SSH port exposed by RunPod"
    echo ""
    echo "Options:"
    echo "  -u, --user USER   SSH username (default: root)"
    echo "  -k, --key PATH    SSH private key path (default: ~/.ssh/id_rsa)"
    echo "  -d, --dry-run     Show what would be synced without making changes"
    echo "  -v, --verbose     Enable verbose output"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 22"
    echo "  $0 192.168.1.100 22 --user ubuntu --key ~/.ssh/runpod_key"
    echo "  $0 192.168.1.100 22 --dry-run --verbose"
    echo ""
    echo "Configuration:"
    echo "  Edit config/runpod.conf to set default SSH settings and paths"
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

pull_workflows() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local dry_run_flag=""
    local verbose_flag=""
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        dry_run_flag="--dry-run"
        echo "DRY RUN MODE: No files will be modified"
        echo ""
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        verbose_flag="-v"
    fi
    
    echo "Pulling workflows from RunPod to local directory..."
    echo "Remote: $user@$ip:$port:$RUNPOD_WORKFLOWS_PATH"
    echo "Local: $LOCAL_WORKFLOWS_DIR"
    echo ""
    
    # Create local directory if it doesn't exist
    mkdir -p "$LOCAL_WORKFLOWS_DIR"
    
    # Pull workflows via rsync over SSH
    rsync -avz $dry_run_flag $verbose_flag \
        --delete \
        --exclude="*.tmp" \
        --exclude=".DS_Store" \
        --exclude="__pycache__/" \
        -e "ssh -i '$key' -p $port -o StrictHostKeyChecking=no" \
        "$user@$ip:$RUNPOD_WORKFLOWS_PATH/" \
        "$LOCAL_WORKFLOWS_DIR/"
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        echo ""
        echo "Pull completed successfully!"
        echo "Local workflows directory: $LOCAL_WORKFLOWS_DIR"
        echo "Files synced:"
        find "$LOCAL_WORKFLOWS_DIR" -type f -name "*.json" | wc -l | xargs echo "  Workflow files:"
    fi
}

main() {
    local ip=""
    local port=""
    local dry_run=false
    local verbose=false
    
    # Check for required arguments
    if [[ $# -lt 2 ]]; then
        echo "Error: IP address and SSH port are required"
        usage
        exit 1
    fi
    
    ip="$1"
    port="$2"
    shift 2
    
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
    
    echo "RunPod ComfyUI Workflow Pull"
    echo "============================="
    echo ""
    
    load_config
    check_dependencies
    
    # Expand tilde in SSH key path
    SSH_KEY="${SSH_KEY/#\~/$HOME}"
    
    # Validate SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Error: SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    test_ssh_connection "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    ensure_remote_rsync "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    pull_workflows "$ip" "$port" "$SSH_USER" "$SSH_KEY"
}

main "$@"