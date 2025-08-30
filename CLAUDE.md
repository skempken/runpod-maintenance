# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Collection of bash scripts for automating maintenance tasks on remote RunPod instances running ComfyUI. Scripts use SSH/rsync for reliable file synchronization and management.

## Commands

### Setup
```bash
# Copy and configure settings
cp config/runpod.conf.example config/runpod.conf
# Edit config/runpod.conf with your SSH settings and paths
```

### Workflow Sync (SSH-based)
```bash
# Auto-detect running pod (requires runpodctl)
./scripts/pull-workflows.sh
./scripts/push-workflows.sh

# Explicit IP and port
./scripts/pull-workflows.sh <IP_ADDRESS> <SSH_PORT>
./scripts/push-workflows.sh <IP_ADDRESS> <SSH_PORT>

# Examples with options
./scripts/pull-workflows.sh --dry-run --verbose              # Auto-detect with options
./scripts/push-workflows.sh --clean                          # Auto-detect with clean mode
./scripts/pull-workflows.sh 192.168.1.100 22 --verbose      # Explicit IP with options
./scripts/push-workflows.sh 192.168.1.100 22 --user ubuntu  # Explicit with custom user
```

### Output Management (SSH-based)
```bash
# Auto-detect running pod and move outputs (default behavior)
./scripts/pull-outputs.sh

# Explicit IP and port with move
./scripts/pull-outputs.sh <IP_ADDRESS> <SSH_PORT>

# Examples with options
./scripts/pull-outputs.sh --dry-run --verbose               # Auto-detect with options
./scripts/pull-outputs.sh --copy                            # Copy instead of move (leave on remote)
./scripts/pull-outputs.sh 192.168.1.100 22 --verbose       # Explicit IP with options
./scripts/pull-outputs.sh 192.168.1.100 22 --copy          # Explicit with copy mode
```


## Architecture

### Directory Structure
- `scripts/` - Executable bash scripts for RunPod maintenance
- `config/` - Configuration files (credentials stored here)
- `workflows/` - Local copy of synced ComfyUI workflows
- `outputs/` - Downloaded ComfyUI generated outputs (organized by timestamp)

### Configuration System
All scripts source `config/runpod.conf` for:
- SSH connection settings (user, key path)
- Remote path mappings

Scripts validate required environment variables and provide helpful error messages for missing configuration.

### Error Handling
- All scripts use `set -euo pipefail` for strict error handling
- Dependencies are checked before execution
- SSH connectivity is tested before synchronization
- Comprehensive validation of parameters and paths

## Dependencies

- rsync (for file synchronization)
- ssh (for secure connections)  
- SSH key configured for RunPod instance access
- runpodctl (for auto-detection, optional)