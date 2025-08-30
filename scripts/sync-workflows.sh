#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/runpod.conf"
LOCAL_WORKFLOWS_DIR="${SCRIPT_DIR}/../workflows"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Sync ComfyUI workflows from RunPod S3 to local folder"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run     Show what would be synced without making changes"
    echo "  -v, --verbose     Enable verbose output"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Configuration:"
    echo "  Edit config/runpod.conf to set your RunPod credentials and paths"
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
    if [[ -z "${RUNPOD_S3_ENDPOINT:-}" ]] || [[ -z "${RUNPOD_S3_BUCKET:-}" ]] || \
       [[ -z "${RUNPOD_S3_ACCESS_KEY:-}" ]] || [[ -z "${RUNPOD_S3_SECRET_KEY:-}" ]] || \
       [[ -z "${RUNPOD_WORKFLOWS_PATH:-}" ]]; then
        echo "Error: Missing required configuration in $CONFIG_FILE"
        echo "Required variables: RUNPOD_S3_ENDPOINT, RUNPOD_S3_BUCKET, RUNPOD_S3_ACCESS_KEY, RUNPOD_S3_SECRET_KEY, RUNPOD_WORKFLOWS_PATH"
        exit 1
    fi
}

check_dependencies() {
    if ! command -v aws >/dev/null 2>&1; then
        echo "Error: AWS CLI not found. Please install it:"
        echo "  macOS: brew install awscli"
        echo "  Linux: apt-get install awscli or yum install awscli"
        exit 1
    fi
}

configure_aws() {
    # Configure AWS CLI for RunPod S3
    export AWS_ACCESS_KEY_ID="$RUNPOD_S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$RUNPOD_S3_SECRET_KEY"
    export AWS_DEFAULT_REGION="${RUNPOD_S3_REGION:-us-east-1}"
}

sync_workflows() {
    local dry_run_flag=""
    local verbose_flag=""
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        dry_run_flag="--dryrun"
        echo "DRY RUN MODE: No files will be modified"
        echo ""
    fi
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        verbose_flag="--cli-read-timeout 0 --cli-connect-timeout 60"
    fi
    
    echo "Syncing workflows from RunPod to local directory..."
    echo "Remote path: s3://$RUNPOD_S3_BUCKET/$RUNPOD_WORKFLOWS_PATH"
    echo "Local path: $LOCAL_WORKFLOWS_DIR"
    echo ""
    
    # Create local directory if it doesn't exist
    mkdir -p "$LOCAL_WORKFLOWS_DIR"
    
    # Sync workflows from S3
    aws s3 sync \
        --endpoint-url "$RUNPOD_S3_ENDPOINT" \
        $verbose_flag \
        $dry_run_flag \
        --delete \
        --exclude "*.tmp" \
        --exclude ".DS_Store" \
        "s3://$RUNPOD_S3_BUCKET/$RUNPOD_WORKFLOWS_PATH" \
        "$LOCAL_WORKFLOWS_DIR"
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        echo ""
        echo "Sync completed successfully!"
        echo "Local workflows directory: $LOCAL_WORKFLOWS_DIR"
    fi
}

main() {
    local dry_run=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
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
    
    echo "RunPod ComfyUI Workflow Sync"
    echo "============================"
    echo ""
    
    load_config
    check_dependencies
    configure_aws
    sync_workflows
}

main "$@"