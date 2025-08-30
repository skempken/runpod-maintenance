#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_WORKFLOWS_DIR="${SCRIPT_DIR}/../workflows"

# Source the shared library
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/runpod-common.sh"

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
    
    load_runpod_config
    check_runpod_dependencies
    check_local_workflows
    
    # Auto-detect pod details if needed
    if [[ "$auto_detect" == "true" ]]; then
        detect_runpod_details
        ip="$DETECTED_POD_IP"
        port="$DETECTED_POD_SSH_PORT"
    fi
    
    setup_runpod_ssh_key
    prepare_runpod_connection "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    ensure_remote_directory "$ip" "$port" "$SSH_USER" "$SSH_KEY"
    push_workflows "$ip" "$port" "$SSH_USER" "$SSH_KEY"
}

main "$@"