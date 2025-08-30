#!/bin/bash

# Pull ComfyUI generated outputs from RunPod instance via SSH/rsync
#
# Copyright (c) 2025 Sebastian Kempken
# Licensed under the MIT License - see LICENSE file for details

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared library
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/runpod-common.sh"

usage() {
    echo "Usage: $0 [IP_ADDRESS] [SSH_PORT] [OPTIONS]"
    echo "Pull ComfyUI generated outputs from RunPod instance via SSH/rsync"
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
    echo "  --copy            Copy files instead of moving them (leave originals on remote)"
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
    echo ""
    echo "Output organization:"
    echo "  Files are saved to LOCAL_OUTPUTS_PATH/YYYY-MM-DD_HH-MM-SS/"
    echo "  This prevents accidental overwrites from multiple sync sessions"
    echo ""
    echo "Default behavior:"
    echo "  Files are MOVED from remote (deleted after successful transfer)"
    echo "  Empty directories on remote are cleaned up after transfer"
    echo "  Use --copy to leave original files on the remote pod"
}

create_timestamped_output_dir() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    
    if [[ -z "${LOCAL_OUTPUTS_PATH:-}" ]]; then
        LOCAL_TIMESTAMPED_DIR="${SCRIPT_DIR}/../outputs/${timestamp}"
    else
        LOCAL_TIMESTAMPED_DIR="${LOCAL_OUTPUTS_PATH}/${timestamp}"
    fi
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        echo "Creating timestamped output directory: $LOCAL_TIMESTAMPED_DIR"
        mkdir -p "$LOCAL_TIMESTAMPED_DIR"
    else
        echo "Would create timestamped directory: $LOCAL_TIMESTAMPED_DIR"
    fi
}

cleanup_remote_directories() {
    local ip="$1"
    local port="$2" 
    local user="$3"
    local key="$4"
    
    echo "Cleaning up empty directories on remote..."
    
    # Remove empty directories from remote, starting from deepest level
    ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no "$user@$ip" \
        "find '$RUNPOD_OUTPUTS_PATH' -type d -empty -delete 2>/dev/null || true"
}

pull_outputs() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local dry_run_flag=""
    local verbose_flag=""
    local remove_source_flag=""
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        dry_run_flag="--dry-run"
        echo "DRY RUN MODE: No files will be modified"
        echo ""
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        verbose_flag="-v"
    fi
    
    if [[ "${COPY_MODE:-false}" != "true" ]]; then
        remove_source_flag="--remove-source-files"
        echo "MOVE MODE: Files will be deleted from remote after successful transfer"
    else
        echo "COPY MODE: Files will be left on remote after transfer"
    fi
    
    # Always create the timestamped directory path for display
    create_timestamped_output_dir
    
    echo "Pulling generated outputs from RunPod to local directory..."
    echo "Remote: $user@$ip:$port:$RUNPOD_OUTPUTS_PATH"
    echo "Local: $LOCAL_TIMESTAMPED_DIR"
    echo ""
    
    # Pull all files via rsync over SSH with recursive directory preservation
    rsync -avz $dry_run_flag $verbose_flag $remove_source_flag \
        --exclude="*.tmp" \
        --exclude="*.temp" \
        --exclude=".DS_Store" \
        --exclude="__pycache__/" \
        -e "ssh -i '$key' -p $port -o StrictHostKeyChecking=no" \
        "$user@$ip:$RUNPOD_OUTPUTS_PATH/" \
        "${LOCAL_TIMESTAMPED_DIR:-/tmp/dry-run}/"
    
    # Clean up empty directories on remote after successful move
    if [[ "${DRY_RUN:-false}" != "true" && "${COPY_MODE:-false}" != "true" ]]; then
        cleanup_remote_directories "$ip" "$port" "$user" "$key"
    fi
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        echo ""
        local action="downloaded"
        if [[ "${COPY_MODE:-false}" != "true" ]]; then
            action="moved"
        fi
        echo "Pull completed successfully!"
        echo "Local outputs directory: $LOCAL_TIMESTAMPED_DIR"
        echo "Files ${action}:"
        find "$LOCAL_TIMESTAMPED_DIR" -type f | wc -l | xargs echo "  Total files:"
    fi
}

main() {
    local ip=""
    local port=""
    local dry_run=false
    local verbose=false
    local copy_mode=false
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
            --copy)
                copy_mode=true
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
    export COPY_MODE=$copy_mode
    
    echo "RunPod ComfyUI Output Pull"
    echo "=========================="
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
    pull_outputs "$ip" "$port" "$SSH_USER" "$SSH_KEY"
}

main "$@"