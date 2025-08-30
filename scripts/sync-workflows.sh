#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "DEPRECATED: sync-workflows.sh"
    echo ""
    echo "This script is deprecated due to RunPod S3 API reliability issues."
    echo "Please use the new SSH-based sync scripts instead:"
    echo ""
    echo "To pull workflows from RunPod:"
    echo "  ./scripts/pull-workflows.sh <IP_ADDRESS> <SSH_PORT> [OPTIONS]"
    echo ""
    echo "To push workflows to RunPod:"
    echo "  ./scripts/push-workflows.sh <IP_ADDRESS> <SSH_PORT> [OPTIONS]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/pull-workflows.sh 192.168.1.100 22"
    echo "  ./scripts/push-workflows.sh 192.168.1.100 22 --dry-run"
    echo ""
    echo "For more information:"
    echo "  ./scripts/pull-workflows.sh --help"
    echo "  ./scripts/push-workflows.sh --help"
}

main() {
    echo ""
    usage
    echo ""
    echo "Migration note:"
    echo "The new SSH-based scripts provide more reliable synchronization"
    echo "and don't require AWS CLI configuration."
    echo ""
    exit 1
}

main "$@"