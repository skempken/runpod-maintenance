#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "DEPRECATED: sync-workflows.sh"
    echo ""
    echo "This script has been replaced with SSH-based sync scripts."
    echo "Please use the new scripts instead:"
    echo ""
    echo "To pull workflows from RunPod:"
    echo "  ./scripts/pull-workflows.sh <IP_ADDRESS> <SSH_PORT> [OPTIONS]"
    echo ""
    echo "To push workflows to RunPod:"
    echo "  ./scripts/push-workflows.sh <IP_ADDRESS> <SSH_PORT> [OPTIONS]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/pull-workflows.sh 192.168.1.100 22"
    echo "  ./scripts/push-workflows.sh 192.168.1.100 22 --clean"
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
    echo "The new SSH-based scripts provide reliable synchronization"
    echo "using rsync over SSH connections."
    echo ""
    exit 1
}

main "$@"