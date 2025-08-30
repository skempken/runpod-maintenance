#!/bin/bash

# RunPod Model Download Script
# Downloads Hugging Face models directly to remote RunPod instance
#
# Usage:
#   ./download-models.sh [OPTIONS] <MODEL_TYPE> <MODEL_REPO> [FILE_PATTERN]
#   ./download-models.sh [OPTIONS] <IP_ADDRESS> <SSH_PORT> <MODEL_TYPE> <MODEL_REPO> [FILE_PATTERN]
#
# Model Types: diffusion_models, vae, clip
#
# Examples:
#   ./download-models.sh diffusion_models runwayml/stable-diffusion-v1-5
#   ./download-models.sh --dry-run vae stabilityai/sd-vae-ft-mse
#   ./download-models.sh 192.168.1.100 22 clip openai/clip-vit-large-patch14
#   ./download-models.sh diffusion_models runwayml/stable-diffusion-v1-5 "*.safetensors"
#   ./download-models.sh vae stabilityai/sd-vae-ft-mse "diffusion_pytorch_model.safetensors"
#
# Copyright (c) 2025 Sebastian Kempken
# Licensed under the MIT License - see LICENSE file for details

set -euo pipefail

# Get script directory and load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runpod-common.sh
source "$SCRIPT_DIR/runpod-common.sh"

# Initialize variables
DRY_RUN=false
VERBOSE=false
IP_ADDRESS=""
SSH_PORT=""
SSH_USER=""
SSH_KEY=""
MODEL_REPO=""
MODEL_TYPE=""
FILE_PATTERN=""

show_usage() {
    cat << 'EOF'
Usage:
  ./download-models.sh [OPTIONS] <MODEL_TYPE> <MODEL_REPO> [FILE_PATTERN]
  ./download-models.sh [OPTIONS] <IP_ADDRESS> <SSH_PORT> <MODEL_TYPE> <MODEL_REPO> [FILE_PATTERN]

Model Types:
  diffusion_models - Main stable diffusion models
  vae              - VAE models
  clip             - CLIP models

Options:
  --dry-run        Show what would be downloaded without executing
  --verbose        Show detailed output
  --user USER      Override SSH username
  --help           Show this help message

Arguments:
  MODEL_TYPE       Target model type (diffusion_models, vae, clip)
  MODEL_REPO       Hugging Face model repository (e.g., runwayml/stable-diffusion-v1-5)
  FILE_PATTERN     Optional file pattern or specific filename to download
                   Examples: "*.safetensors", "model.ckpt", "diffusion_pytorch_model.safetensors"
                   If omitted, downloads entire repository

Examples:
  # Auto-detect running pod
  ./download-models.sh diffusion_models runwayml/stable-diffusion-v1-5
  ./download-models.sh vae stabilityai/sd-vae-ft-mse
  ./download-models.sh clip openai/clip-vit-large-patch14
  
  # Download specific files
  ./download-models.sh diffusion_models runwayml/stable-diffusion-v1-5 "*.safetensors"
  ./download-models.sh vae stabilityai/sd-vae-ft-mse "diffusion_pytorch_model.safetensors"
  
  # Explicit IP and port
  ./download-models.sh 192.168.1.100 22 diffusion_models runwayml/stable-diffusion-v1-5
  
  # With options
  ./download-models.sh --dry-run --verbose diffusion_models runwayml/stable-diffusion-v1-5 "*.ckpt"
  ./download-models.sh --user ubuntu 192.168.1.100 22 vae stabilityai/sd-vae-ft-mse

EOF
}

validate_model_type() {
    local model_type="$1"
    case "$model_type" in
        diffusion_models|vae|clip)
            return 0
            ;;
        *)
            echo "Error: Invalid model type '$model_type'"
            echo "Valid types: diffusion_models, vae, clip"
            exit 1
            ;;
    esac
}

get_model_path_for_type() {
    local model_type="$1"
    case "$model_type" in
        diffusion_models)
            echo "$RUNPOD_DIFFUSION_MODELS_PATH"
            ;;
        vae)
            echo "$RUNPOD_VAE_MODELS_PATH"
            ;;
        clip)
            echo "$RUNPOD_CLIP_MODELS_PATH"
            ;;
    esac
}

check_hf_cli_on_remote() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local hf_cli_path="$5"
    
    echo "Checking Hugging Face CLI availability on remote system..."
    
    if ! ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no "$user@$ip" \
         "command -v '$hf_cli_path' >/dev/null 2>&1" 2>/dev/null; then
        echo "Error: Hugging Face CLI not found at: $hf_cli_path"
        echo "Please install huggingface-hub on the RunPod instance:"
        echo "  pip install huggingface-hub"
        echo "Or update RUNPOD_HF_CLI_PATH in your configuration"
        exit 1
    fi
    
    echo "Hugging Face CLI found at: $hf_cli_path"
}

download_model() {
    local ip="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local model_repo="$5"
    local target_path="$6"
    local hf_cli_path="$7"
    local file_pattern="$8"
    
    echo "Downloading model: $model_repo"
    if [[ -n "$file_pattern" ]]; then
        echo "File pattern: $file_pattern"
    fi
    echo "Target path: $target_path"
    
    # Build environment variables for remote execution
    local env_vars=""
    if [[ -n "${HF_TOKEN:-}" ]]; then
        env_vars="$env_vars HF_TOKEN='$HF_TOKEN'"
    fi
    if [[ -n "${HF_HUB_CACHE:-}" ]]; then
        env_vars="$env_vars HF_HUB_CACHE='$HF_HUB_CACHE'"
    fi
    if [[ -n "${HF_XET_HIGH_PERFORMANCE:-}" ]]; then
        env_vars="$env_vars HF_XET_HIGH_PERFORMANCE='$HF_XET_HIGH_PERFORMANCE'"
    fi
    if [[ -n "${HF_HUB_ENABLE_HF_TRANSFER:-}" ]]; then
        env_vars="$env_vars HF_HUB_ENABLE_HF_TRANSFER='$HF_HUB_ENABLE_HF_TRANSFER'"
    fi
    
    # Build the remote command
    local download_cmd="'$hf_cli_path' download '$model_repo' --local-dir ."
    if [[ -n "$file_pattern" ]]; then
        download_cmd="$download_cmd --include '$file_pattern'"
    fi
    local remote_cmd="mkdir -p '$target_path' && cd '$target_path' && $env_vars $download_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute on remote:"
        echo "  $remote_cmd"
        return 0
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Executing remote command:"
        echo "  $remote_cmd"
    fi
    
    # Execute the download command on the remote system
    if ssh -i "$key" -p "$port" -o StrictHostKeyChecking=no "$user@$ip" "$remote_cmd"; then
        echo "Model download completed successfully!"
        echo "Model location: $user@$ip:$target_path"
    else
        echo "Error: Model download failed"
        exit 1
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --user)
                SSH_USER="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option $1"
                show_usage
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Parse positional arguments
    if [[ $# -eq 2 ]]; then
        # Format: MODEL_TYPE MODEL_REPO
        MODEL_TYPE="$1"
        MODEL_REPO="$2"
    elif [[ $# -eq 3 ]]; then
        # Format: MODEL_TYPE MODEL_REPO FILE_PATTERN
        MODEL_TYPE="$1"
        MODEL_REPO="$2"
        FILE_PATTERN="$3"
    elif [[ $# -eq 4 ]]; then
        # Format: IP_ADDRESS SSH_PORT MODEL_TYPE MODEL_REPO
        IP_ADDRESS="$1"
        SSH_PORT="$2"
        MODEL_TYPE="$3"
        MODEL_REPO="$4"
    elif [[ $# -eq 5 ]]; then
        # Format: IP_ADDRESS SSH_PORT MODEL_TYPE MODEL_REPO FILE_PATTERN
        IP_ADDRESS="$1"
        SSH_PORT="$2"
        MODEL_TYPE="$3"
        MODEL_REPO="$4"
        FILE_PATTERN="$5"
    else
        echo "Error: Invalid number of arguments"
        show_usage
        exit 1
    fi
    
    validate_model_type "$MODEL_TYPE"
}

main() {
    parse_arguments "$@"
    
    # Load configuration
    load_runpod_config
    check_runpod_dependencies
    
    # Validate HF CLI path is configured
    if [[ -z "${RUNPOD_HF_CLI_PATH:-}" ]]; then
        echo "Error: Missing required configuration in $RUNPOD_CONFIG_FILE"
        echo "Required variables: RUNPOD_HF_CLI_PATH"
        exit 1
    fi
    
    # Set up SSH connection details
    if [[ -z "$IP_ADDRESS" ]]; then
        detect_runpod_details
        IP_ADDRESS="$DETECTED_POD_IP"
        SSH_PORT="$DETECTED_POD_SSH_PORT"
    fi
    
    # Set SSH user and key with overrides
    SSH_USER="${SSH_USER:-${RUNPOD_SSH_USER:-root}}"
    SSH_KEY="${SSH_KEY:-${RUNPOD_SSH_KEY_PATH:-~/.ssh/id_rsa}}"
    
    setup_runpod_ssh_key
    
    echo "=== RunPod Model Download ==="
    echo "Pod: $IP_ADDRESS:$SSH_PORT"
    echo "Model: $MODEL_REPO"
    echo "Type: $MODEL_TYPE"
    if [[ -n "$FILE_PATTERN" ]]; then
        echo "Files: $FILE_PATTERN"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY RUN"
    fi
    echo
    
    # Test connection and check dependencies
    test_runpod_ssh_connection "$IP_ADDRESS" "$SSH_PORT" "$SSH_USER" "$SSH_KEY"
    check_hf_cli_on_remote "$IP_ADDRESS" "$SSH_PORT" "$SSH_USER" "$SSH_KEY" "$RUNPOD_HF_CLI_PATH"
    
    # Get target path for the model type
    TARGET_PATH=$(get_model_path_for_type "$MODEL_TYPE")
    
    # Download the model
    download_model "$IP_ADDRESS" "$SSH_PORT" "$SSH_USER" "$SSH_KEY" "$MODEL_REPO" "$TARGET_PATH" "$RUNPOD_HF_CLI_PATH" "$FILE_PATTERN"
    
    echo "Model download process completed!"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi