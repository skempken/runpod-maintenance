#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_WORKFLOWS_DIR="${SCRIPT_DIR}/../workflows"

# Source the shared library
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/runpod-common.sh"

usage() {
    echo "Usage: $0 [IP_ADDRESS] [SSH_PORT] [OPTIONS]"
    echo "Pull ComfyUI workflows from RunPod instance via SSH/rsync"
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
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect running pod"
    echo "  $0 192.168.1.100 22                  # Explicit IP and port"
    echo "  $0 --dry-run --verbose               # Auto-detect with options"
    echo "  $0 192.168.1.100 22 --user ubuntu   # Explicit with options"
    echo ""
    echo "Auto-detection requirements:"
    echo "  - runpodctl must be installed and configured"
    echo "  - Exactly one pod must be running"
    echo ""
    echo "Configuration:"
    echo "  Edit config/runpod.conf to set default SSH settings and paths"
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
    
    load_runpod_config
    check_runpod_dependencies
    
    # Auto-detect pod details if needed
    if [[ "$auto_detect" == "true" ]]; then
        detect_runpod_details
        ip="$DETECTED_POD_IP"
        port="$DETECTED_POD_SSH_PORT"
    fi
    
    setup_runpod_ssh_key
    prepare_runpod_connection "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    pull_workflows "$ip" "$port" "$SSH_USER" "$SSH_KEY"
}

main "$@"