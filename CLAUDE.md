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
# Pull workflows from RunPod to local
./scripts/pull-workflows.sh <IP_ADDRESS> <SSH_PORT>

# Push workflows from local to RunPod
./scripts/push-workflows.sh <IP_ADDRESS> <SSH_PORT>

# Examples with options
./scripts/pull-workflows.sh 192.168.1.100 22 --dry-run --verbose
./scripts/push-workflows.sh 192.168.1.100 22 --user ubuntu --key ~/.ssh/runpod_key
./scripts/push-workflows.sh 192.168.1.100 22 --clean
```


## Architecture

### Directory Structure
- `scripts/` - Executable bash scripts for RunPod maintenance
- `config/` - Configuration files (credentials stored here)
- `workflows/` - Local copy of synced ComfyUI workflows

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